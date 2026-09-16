%% experiments/exp_dd_refine.m
% 目的: 在【理想切分】(跳过帧检测, 隔离估计器影响) 下比较各频偏补偿方案
%       背景: exp_freq_estimator 证明算法已无空间(ML仅好7%, 重复结构反而差);
%              exp_preamble_len_e2e 证明加长前导有效(p=64: 12dB 35%->95%)
%       本实验: 再加两条零带宽方案对照 —— 判决导向(DD)频偏精估、以及性能上界
%
% 关键修正(上一版两个缺陷):
%   1) 成功判据: 必须比对【整条 62 字节消息】, 不能只比前 4 字符
%   2) 残余频偏诊断: 必须用 fTot - 注入真值, 不能校正后再从前导测(循环测量)
% 用法: matlab -batch "addpath('experiments'); exp_dd_refine"

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;
Rs = params.SymbolRate;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
ref = pskmod((0:M-1).', M);

nF = 20; freqOffset = 320; nRep = 3;
modes = {'现状(前导两段)','+1次DD精估','+2次DD精估','前导加长到64','理想(用真值)'};
nMode = numel(modes);

fprintf('\n############ 频偏补偿方案对比 (理想切分) ############\n');
fprintf('满载荷 62 字节, %d 帧 x %d 次, 注入频偏 %d Hz\n', nF, nRep, freqOffset);

for dB = [10 12 14]
    fprintf('\n=== Eb/N0 = %d dB ===\n', dB);
    fprintf('%-18s | %10s | %14s\n', '方案', '解帧成功率', '频偏误差std(Hz)');
    fprintf('%s\n', repmat('-', 1, 48));
    for mode = 1:nMode
        p = params.PreambleSym; if mode == 4, p = 64; end
        params2 = params; params2.PreambleSym = p;
        [~, scr2, pre2] = gen_frame_sequences(params2);
        Nsym2 = p + params2.HeaderSym + params2.PayloadSym;
        t2 = (0:Nsym2-1).'/Rs;
        stride = Nsym2*L + length(rrc) - 1 + 80;

        totOK = 0; totN = 0; errArr = [];
        for tr = 1:nRep
            rng(300*tr + dB);
            cw = []; msgs = {};
            for k = 1:nF
                m = [sprintf('PKT-%03d-', k-1) repmat('X', 1, 54)];
                msgs{k} = m;
                fS = tx_frame(int8(m(:)), params2, 0, mod(k-1,256));
                [w, ~] = tx_baseband(fS, L, rrc);
                w = w*0.9/max(abs(w));
                if k == 1, Es = L*mean(abs(w).^2); end
                cw = [cw; w; zeros(80,1)]; %#ok<AGROW>
            end
            nn = (0:length(cw)-1).';
            cw = cw .* exp(1j*2*pi*freqOffset*nn/params2.SampleRate);
            sg = sqrt(Es/(2*10^(dB/10)*bp));
            cw = cw + sg*(randn(size(cw))+1j*randn(size(cw)));

            for k = 1:nF
                st = (k-1)*stride + 1;
                en = min(st + Nsym2*L + length(rrc) - 1, length(cw));
                [txt, fer] = rxOneFrame(cw(st:en), params2, rrc, pre2, mode, t2, ref, M, bp, freqOffset);
                if strcmp(txt, msgs{k}), totOK = totOK + 1; end
                totN = totN + 1;
                errArr(end+1) = fer; %#ok<AGROW>
            end
        end
        fprintf('%-18s | %9.1f%% | %13.1f Hz\n', modes{mode}, totOK/totN*100, std(errArr));
    end
end
fprintf('\n注: "理想(用真值)"= 用已知的真实频偏 320 Hz 补偿, 作为性能上界参照\n');

%% ================= 局部函数 =================
function [txt, freqErr] = rxOneFrame(rxWave, params, rrc, preSym, mode, tSym, ref, M, bp, fTrue)
% 返回: 解出的文本, 以及【估计频偏 - 真值】的误差
    L = params.SamplesPerSym;  p = params.PreambleSym;  Rs = params.SymbolRate;
    Nsym = p + params.HeaderSym + params.PayloadSym;

    mf = conv(rxWave, rrc);
    peak = length(rrc);
    rs = mf(peak : L : peak + (Nsym-1)*L);

    if mode == 5
        % 理想: 用真值补偿
        fTot = fTrue;
        rc = rs .* exp(-1j*2*pi*fTrue*tSym);
    else
        [f1, rc] = freq_sync(rs, preSym, L, Rs);
        fTot = f1;
        nIter = 0;
        if mode == 2, nIter = 1; end
        if mode == 3, nIter = 2; end
        for it = 1:nIter
            ph = angle(mean(rc(1:p) .* conj(preSym(:))));
            rcc = rc * exp(-1j*ph);
            [~, mi] = min(abs(rcc.' - ref).^2, [], 1);
            sHat = ref(mi).';
            d = rcc .* conj(sHat);
            df = estML(d, Rs);
            rc = rc .* exp(-1j*2*pi*df*tSym);
            fTot = fTot + df;
        end
    end

    % 最终常数相位校正 + 判决
    ph = angle(mean(rc(1:p) .* conj(preSym(:))));
    rc = rc * exp(-1j*ph);
    [~, mi] = min(abs(rc.' - ref).^2, [], 1);
    symIdx = (mi - 1).';
    freqErr = fTot - fTrue;

    % --- 解帧 ---
    bitsRx = reshape(de2bi(symIdx, bp, 'left-msb').', [], 1);
    nP = p*bp; nH = params.HeaderSym*bp;
    hdr = bitsRx(nP+1 : nP+nH);
    hType = bi2de(hdr(1:2).', 'left-msb');
    hLen  = bi2de(hdr(3:10).', 'left-msb');
    nb = min(hLen, 62);
    txt = '';
    if nb < 1 || nb > 62 || ~isequal(hType, 0), return; end
    payloadBits = xor(bitsRx(nP+nH+1 : end), genScrambler(params));
    bb = reshape(payloadBits(1:nb*8), 8, []).';
    txt = char(bi2de(bb, 'left-msb')).';
end

function sc = genScrambler(params)
    [~, sc, ~] = gen_frame_sequences(params);
end

function fh = estML(d, Rs)
    d = d(:);
    Nfft = 2^16;
    F = fftshift(fft(d, Nfft));
    m = abs(F);
    [~, i] = max(m);  i = i(1);
    ax = (-Nfft/2:Nfft/2-1).'/Nfft*Rs;
    if i > 1 && i < Nfft
        a = m(i-1); b = m(i); c = m(i+1);
        den = (a - 2*b + c);
        delta = 0; if abs(den) > eps, delta = 0.5*(a-c)/den; end
        fh = ax(i) + delta*(Rs/Nfft);
    else
        fh = ax(i);
    end
end
