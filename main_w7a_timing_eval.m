%% main_w7a_timing_eval.m
% W7a 决策评估: 是否需要"定时精调"?
%
% 动机: DD-PLL 已把 8 dB 解帧率拉到 90%、10 dB 拉到 100%,
%       定时精调的边际收益不确定。本脚本先量化, 再决定是否投入。
%
% 两步:
%   A. 当前系统的【实际残余定时误差】有多大?
%      —— 相关峰给出的整数抽样位置 vs 真正的最佳抽样位置(最大眼图开口)
%   B. 定时误差对 BER 的影响 (开/关 PLL)
%      —— 受控采样相位偏移 delta 扫描
%
% 用法: matlab -batch "main_w7a_timing_eval"

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;
Rs = params.SymbolRate;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, preSym] = gen_frame_sequences(params);
Nsym = params.PreambleSym + params.HeaderSym + params.PayloadSym;
peak = length(rrc);
ref  = pskmod((0:M-1).', M);

msg  = [sprintf('PKT-%03d-',0) repmat('X',1,54)];
fSym = tx_frame(int8(msg(:)), params, 0, 0);
sIdxTx = pskdemod(fSym, M);
bTx = reshape(de2bi(sIdxTx, bp, 'left-msb').', [], 1);

fprintf('\n################################################################\n');
fprintf('#   W7a 决策评估: 定时精调是否必要?                             #\n');
fprintf('################################################################\n');

%% ===== A. 当前系统的实际残余定时误差 =====
fprintf('\n===== A. 残余定时误差测量 =====\n');
fprintf('方法: 相关峰给出整数抽样位置; 真实最佳位置用"最大眼图开口"搜索\n');
fprintf('      (匹配滤波输出 |s|^2 之和最大处), 两者之差即残余定时误差\n\n');

dB = 10;
NT = 300;
deltas = -0.5 : 0.05 : 0.5;
err = zeros(NT,1);
for tr = 1:NT
    rng(3000+tr);
    [w,~] = tx_baseband(fSym, L, rrc); w = w*0.9/max(abs(w));
    Es = L*mean(abs(w).^2);
    sg = sqrt(Es/(2*10^(dB/10)*bp));
    nn = (0:length(w)-1).';
    rx = w .* exp(1j*2*pi*320*nn/params.SampleRate);
    rx = rx + sg*(randn(size(rx))+1j*randn(size(rx)));

    % 相关峰 (实际系统用的方法) -> 整数帧起点
    preUp = zeros(params.PreambleSym*L,1); preUp(1:L:end) = preSym;
    pw = conv(preUp, rrc);
    fs_ = frame_detect(rx, pw, L);
    if isnan(fs_), err(tr) = NaN; continue; end

    % 搜索最佳小数抽样位置
    mf = conv(rx(fs_:end), rrc);
    best = -inf; bd = 0;
    for d = deltas
        y = fracDelay(mf, d);
        idx = peak : L : peak + (Nsym-1)*L;
        if idx(end) > numel(y), continue; end
        p = sum(abs(y(idx)).^2);
        if p > best, best = p; bd = d; end
    end
    err(tr) = bd;
end
e = err(~isnan(err));
fprintf('  样本数: %d\n', numel(e));
fprintf('  残余定时误差: 均值 %+.3f 采样, 标准差 %.3f 采样, |误差| 均值 %.3f 采样\n', ...
        mean(e), std(e), mean(abs(e)));
fprintf('  折算符号周期: |误差| 均值 = %.3f T  (T = 1/Rs, L=%d 采样/符号)\n', mean(abs(e))/L, L);
fprintf('  误差分布: [<0.15T] %.0f%%   [0.15~0.25T] %.0f%%   [>0.25T] %.0f%%\n', ...
        100*mean(abs(e)/L < 0.15), ...
        100*mean(abs(e)/L >= 0.15 & abs(e)/L < 0.25), ...
        100*mean(abs(e)/L >= 0.25));

%% ===== B. 定时误差对 BER 的影响 (开/关 PLL) =====
fprintf('\n===== B. BER vs 采样相位偏移 (开/关 PLL) =====\n');
dScan = [-0.5 -0.375 -0.25 -0.125 0 0.125 0.25 0.375 0.5];
for dB2 = [8 10]
    fprintf('\n--- Eb/N0 = %d dB ---\n', dB2);
    fprintf('%12s | %16s | %16s\n', '偏移(采样)', 'W6 无PLL', 'W7 有PLL');
    fprintf('%s\n', repmat('-', 1, 50));
    for d = dScan
        berV = zeros(1,2);
        for mode = 1:2
            params.PhaseTrack = (mode == 2);
            acc = 0; NT2 = 300;
            for tr = 1:NT2
                rng(4000+tr);
                rx = mkRx(fSym, L, rrc, params, dB2);
                sIdx = rxChain(rx, d, params, rrc, preSym, M, ref, peak, Nsym, L, Rs);
                bRx = reshape(de2bi(sIdx, bp, 'left-msb').', [], 1);
                acc = acc + mean(bTx ~= bRx);
            end
            berV(mode) = acc/NT2;
        end
        fprintf('%12.3f | %16.3e | %16.3e\n', d, berV(1), berV(2));
    end
end

fprintf('\n################################################################\n');
fprintf('#   评估完成                                                    #\n');
fprintf('################################################################\n\n');

%% ===== C. ★ 真实空口数据的残余定时误差 (决定性测量) =====
fprintf('\n===== C. 真实空口数据的残余定时误差 =====\n');
fprintf('说明: 仿真中帧起点恰好落在整数采样点上, 故 A 部测得 0.004T 属理想情况。\n');
fprintf('      真实空口帧起点相位任意, 这里用【已知前导】直接搜索最佳抽样位置。\n\n');
if exist('results/w3_rxData.mat', 'file')
    S = load('results/w3_rxData.mat');
    rxR = S.rxData(:);
    preUp = zeros(params.PreambleSym*L,1); preUp(1:L:end) = preSym;
    pw = conv(preUp, rrc);
    Np = numel(pw);

    % 用归一化相关找帧起点 (并列出所有候选峰, 循环发射会有多个)
    cf = abs(conv(rxR, conj(flipud(pw))));
    cm = cf(Np : numel(rxR));
    Nc = numel(cm);
    p2 = abs(rxR).^2; cp2 = [0; cumsum(p2)];
    Er = cp2(Np+1:Np+Nc) - cp2(1:Nc);
    rho = cm ./ sqrt(Er * sum(abs(pw).^2));

    pk = find(rho > 0.60);
    if isempty(pk)
        fprintf('  未检出帧 (rho 最大值 %.3f)\n', max(rho));
    else
        % 取前若干个峰 (间隔去重)
        grp = {}; g = pk(1);
        for i = 2:numel(pk)
            if pk(i) - pk(i-1) <= 2, g(end+1) = pk(i); else, grp{end+1} = g; g = pk(i); end
        end
        grp{end+1} = g;
        nUse = min(5, numel(grp));
        fprintf('  检出 %d 个帧起点, 用前 %d 个各自搜索最佳抽样相位\n\n', numel(grp), nUse);

        dGrid = -0.5 : 0.02 : 0.5;
        optD = zeros(nUse,1);
        fprintf('%8s | %14s | %s\n', '帧#', '最佳偏移(采样)', '折算(T)');
        fprintf('%s\n', repmat('-',1,44));
        for i = 1:nUse
            gi = grp{i};
            [~, rel] = max(rho(gi));
            fsR = gi(rel);                      % 整数帧起点
            seg = rxR(fsR : min(fsR + numel(pw) + Nsym*L, numel(rxR)));
            mf = conv(seg, rrc);
            best = -inf; bd = 0;
            for d = dGrid
                y = fracDelay(mf, d);
                idx = peak : L : peak + (params.PreambleSym-1)*L;
                if idx(end) > numel(y), continue; end
                v = abs(sum(y(idx) .* conj(preSym(:))));   % 已知前导相关幅度
                if v > best, best = v; bd = d; end
            end
            optD(i) = bd;
            fprintf('%8d | %+14.2f | %+.4f\n', i-1, bd, bd/L);
        end
        fprintf('\n  真实空口残余定时误差: 均值 %+.3f 采样 (%.4f T), 范围 [%.2f, %.2f] 采样\n', ...
                mean(optD), mean(optD)/L, min(optD), max(optD));
        fprintf('  折算: |误差| 均值 = %.4f T  =>  可用 A 部结果插值估计 BER 退化\n');
        fprintf('        (参见 B 部 8 dB 行: delta=0 时 %.2e, delta=0.25 时 %.2e @W7)\n', ...
                2.196e-4, 5.011e-4);
    end
else
    fprintf('  (未找到 results/w3_rxData.mat, 跳过)\n');
end

fprintf('\n################################################################\n');
fprintf('#   评估完成 (含真实数据)                                       #\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function rx = mkRx(fSym, L, rrc, params, dB)
    [w,~] = tx_baseband(fSym, L, rrc); w = w*0.9/max(abs(w));
    Es = L*mean(abs(w).^2);
    sg = sqrt(Es/(2*10^(dB/10)*params.bitsPerSym));
    nn = (0:length(w)-1).';
    rx = w .* exp(1j*2*pi*320*nn/params.SampleRate);
    rx = rx + sg*(randn(size(rx))+1j*randn(size(rx)));
end

function sIdx = rxChain(rx, d, params, rrc, preSym, M, ref, peak, Nsym, L, Rs)
% 完整接收链, 采样相位可受控偏移 d (采样)
    mf = conv(rx, rrc);
    y  = fracDelay(mf, d);
    idx = peak : L : peak + (Nsym-1)*L;
    if idx(end) > numel(y), sIdx = zeros(Nsym,1); return; end
    rs = y(idx);

    [~, rc] = freq_sync(rs, preSym, L, Rs);
    ph = angle(mean(rc(1:params.PreambleSym) .* conj(preSym(:))));
    rc = rc * exp(-1j*ph);

    usePll = true;
    if isfield(params,'PhaseTrack'), usePll = logical(params.PhaseTrack); end
    if usePll
        mu = 0.10;
        if isfield(params,'PllMu') && ~isempty(params.PllMu), mu = params.PllMu; end
        sIdx = phase_track(rc, preSym, M, mu);
    else
        [~, mi] = min(abs(rc.' - ref).^2, [], 1);
        sIdx = (mi-1).';
    end
end

function y = fracDelay(x, d)
% FFT 小数延时 (信号带宽远小于 fs/2, 精度足够)
    x = x(:);
    N = numel(x);
    if d == 0, y = x; return; end
    F = fft(x);
    fr = (0:N-1).'/N;  fr(fr>0.5) = fr(fr>0.5) - 1;
    y = ifft(F .* exp(-1j*2*pi*fr*d));
end
