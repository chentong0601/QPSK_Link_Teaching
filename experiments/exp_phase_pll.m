%% experiments/exp_phase_pll.m
% 目的: 验证【判决导向 PLL】能否零带宽代价地跟踪帧内相位斜坡 (W7b 关键验证)
%
% 背景(前面的实验链):
%   exp_freq_estimator   : 估计器算法已无空间 (ML 仅好 7%; 重复结构反而差 7.6%)
%   exp_preamble_len_e2e : 加长前导有效 (p=64: 12dB 35%->95%), 但代价 9.8% 吞吐
%   exp_dd_refine        : 批量 DD 频偏精估【失败】(帧尾判决出错 -> 估计崩溃)
% 本实验: 一阶 DD-PLL, 扫描环路增益 mu; 并输出相位跟踪轨迹图
% 用法: matlab -batch "addpath('experiments'); exp_phase_pll"

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;
Rs = params.SymbolRate;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
ref = pskmod((0:M-1).', M);
p = params.PreambleSym;
[~, ~, preSym] = gen_frame_sequences(params);
Nsym = p + params.HeaderSym + params.PayloadSym;
tSym = (0:Nsym-1).'/Rs;
stride = Nsym*L + length(rrc) - 1 + 80;

nF = 20; freqOffset = 320; nRep = 3;
muList = [0.02 0.05 0.10 0.20];

fprintf('\n############ DD-PLL 相位跟踪验证 (W7b) ############\n');
fprintf('满载荷 62 字节, %d 帧 x %d 次, 注入频偏 %d Hz, 前导保持 p=%d\n', ...
        nF, nRep, freqOffset, p);

for dB = [8 10 12 14]
    fprintf('\n=== Eb/N0 = %d dB ===\n', dB);
    fprintf('%-24s | %10s\n', '方案', '解帧成功率');
    fprintf('%s\n', repmat('-', 1, 38));

    nTot = 0; okNow = 0; okIdeal = 0; okPLL = zeros(size(muList));
    thTrace = []; thTrue = [];

    for tr = 1:nRep
        rng(300*tr + dB);
        cw = []; msgs = {};
        for k = 1:nF
            m = [sprintf('PKT-%03d-', k-1) repmat('X', 1, 54)];
            msgs{k} = m;
            fS = tx_frame(int8(m(:)), params, 0, mod(k-1,256));
            [w, ~] = tx_baseband(fS, L, rrc);
            w = w*0.9/max(abs(w));
            if k == 1, Es = L*mean(abs(w).^2); end
            cw = [cw; w; zeros(80,1)]; %#ok<AGROW>
        end
        nn = (0:length(cw)-1).';
        cw = cw .* exp(1j*2*pi*freqOffset*nn/params.SampleRate);
        sg = sqrt(Es/(2*10^(dB/10)*bp));
        cw = cw + sg*(randn(size(cw))+1j*randn(size(cw)));

        for k = 1:nF
            st = (k-1)*stride + 1;
            en = min(st + Nsym*L + length(rrc) - 1, length(cw));
            seg = cw(st:en);
            mf = conv(seg, rrc);
            peak = length(rrc);
            rs = mf(peak : L : peak + (Nsym-1)*L);

            % (a) 现状: 频偏估计 + 常数相位校正
            [~, rc] = freq_sync(rs, preSym, L, Rs);
            ph = angle(mean(rc(1:p) .* conj(preSym(:))));
            sA = decide(rc*exp(-1j*ph), ref);
            okNow = okNow + msgOK(sA, params, bp, p, msgs{k});

            % (b) 理想: 用真实频偏补偿 (性能上界)
            rcI = rs .* exp(-1j*2*pi*freqOffset*tSym);
            phI = angle(mean(rcI(1:p) .* conj(preSym(:))));
            sI = decide(rcI*exp(-1j*phI), ref);
            okIdeal = okIdeal + msgOK(sI, params, bp, p, msgs{k});

            % (c) DD-PLL (扫描 mu)
            for mi = 1:numel(muList)
                [sP, th] = ddpll(rc, preSym, p, muList(mi), ref);
                okPLL(mi) = okPLL(mi) + msgOK(sP, params, bp, p, msgs{k});
                if tr == 1 && k == 1 && mi == 2
                    % 记录轨迹: PLL 跟踪到的相位 theta (含前导初值)
                    thTrace = th;
                    % 真实残余相位: 真频偏减估计频偏造成的斜坡 + 常数
                    [fe, ~] = freq_sync(rs, preSym, L, Rs);
                    thTrue = angle(exp(1j*(2*pi*(freqOffset-fe)*tSym + ph)));
                end
            end
            nTot = nTot + 1;
        end
    end

    fprintf('%-24s | %9.1f%%\n', '现状(前导常数校正)', okNow/nTot*100);
    fprintf('%-24s | %9.1f%%\n', '理想(用真值)',      okIdeal/nTot*100);
    for mi = 1:numel(muList)
        fprintf('%-24s | %9.1f%%\n', sprintf('+DD-PLL mu=%.2f', muList(mi)), okPLL(mi)/nTot*100);
    end
end

%% ---- 相位跟踪轨迹图 (spec §9.2 要求) ----
if ~isempty(thTrace)
    f = figure('Position',[100 100 760 440],'Color','w');
    h1 = plot(0:Nsym-1, unwrap(thTrace)*180/pi, '-', 'LineWidth', 1.8, 'Color', '#185FA5'); hold on;
    h2 = plot(0:Nsym-1, unwrap(thTrue)*180/pi, '--', 'LineWidth', 1.5, 'Color', '#993C1D');
    grid on; box on;
    xlabel('符号序号', 'FontSize',12); ylabel('相位 (度)', 'FontSize',12);
    legend([h1 h2], {'DD-PLL 跟踪相位','真实残余相位'}, 'Location','northwest', 'FontSize',11);
    title('W7b: DD-PLL 相位跟踪轨迹 (一阶, \mu=0.05)', 'FontSize',12);
    lbl = sprintf('前导结束 (p=%d)', p);
    xline(p, ':', lbl, 'Color',[0.5 0.5 0.5], 'FontSize',10);
    if ~isfolder('plots'), mkdir('plots'); end
    saveas(f, fullfile('plots','w7_pll_tracking.png'));
    fprintf('\n[OK] 相位跟踪轨迹已保存 plots/w7_pll_tracking.png\n');
end

%% ================= 局部函数 =================
function [symIdx, thetaHist] = ddpll(rc, preSym, p, mu, ref)
% 一阶判决导向 PLL: 用前导定初相, 逐符号跟踪
    Nsym = length(rc);
    theta = angle(mean(rc(1:p) .* conj(preSym(:))));   % 前导定初值(消解4重模糊)
    symIdx = zeros(Nsym,1);
    thetaHist = zeros(Nsym,1);
    for k = 1:Nsym
        y = rc(k) * exp(-1j*theta);
        [~, mi] = min(abs(y - ref).^2);
        symIdx(k) = mi - 1;
        e = imag(y * conj(ref(mi)));      % 相位误差检测器
        theta = theta + mu*e;             % 一阶环路更新
        thetaHist(k) = theta;
    end
end

function s = decide(x, ref)
    [~, mi] = min(abs(x(:).' - ref).^2, [], 1);
    s = (mi - 1).';
end

function ok = msgOK(symIdx, params, bp, p, msgTrue)
    bitsRx = reshape(de2bi(symIdx, bp, 'left-msb').', [], 1);
    nP = p*bp; nH = params.HeaderSym*bp;
    hdr = bitsRx(nP+1 : nP+nH);
    ok = 0;
    if numel(hdr) < nH, return; end
    hType = bi2de(hdr(1:2).', 'left-msb');
    hLen  = bi2de(hdr(3:10).', 'left-msb');
    nb = min(hLen, 62);
    if nb < 1 || nb > 62 || ~isequal(hType, 0), return; end
    [~, scr, ~] = gen_frame_sequences(params);
    pb = xor(bitsRx(nP+nH+1 : end), scr);
    bb = reshape(pb(1:nb*8), 8, []).';
    txt = char(bi2de(bb, 'left-msb')).';
    ok = double(strcmp(txt, msgTrue));
end
