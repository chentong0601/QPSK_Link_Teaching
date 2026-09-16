%experiments/diag_p6_evm.m  真实空口链路 EVM 分析 (修正版)
%  方法: 用【已知前导】直接计算 EVM (无需判决), 得出真实链路信噪比
%  数据: P6a 各 RxGain 的 rxData + W3 已知良好数据 (作参照)
%  用法: matlab -batch "addpath('experiments'); diag_p6_evm"

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params; L = params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[preambleSym, ~, ~, ~] = frame_sequences_cached(params);
p = numel(preambleSym);

% 前导成形波形 (采样域)
up = zeros(p*L,1); up(1:L:end) = preambleSym;
pw = conv(up, rrc);
Lp = numel(pw);

%% ---------- 1. W3 已知良好数据 (参照) ----------
fprintf('===== 参照: W3 真实空口 (曾解出 "HELLO QPSK!") =====\n');
Sw = load('results/w3_rxData.mat');
if isfield(Sw, 'rxData')
    analyze_rx(Sw.rxData(:), params, rrc, pw, preambleSym, L, 'W3');
end

%% ---------- 2. P6a 各 RxGain ----------
d = dir('results/p6_link_*.mat');
[~, idx] = max([d.datenum]);
S = load(fullfile(d(idx).folder, d(idx).name));
fprintf('\n===== P6a 真实空口 (2026-09-12 实测) =====\n');
for g = 1:numel(S.res)
    if isempty(S.res(g).rxData), continue; end
    analyze_rx(S.res(g).rxData(:), params, rrc, pw, preambleSym, L, ...
               sprintf('P6a RxGain=%d dB', S.res(g).gain));
end

%% ---------- 3. 判决裕量: 前导符号的相位误差分布 ----------
fprintf('\n===== 说明 =====\n');
fprintf('  EVM 与 QPSK 判决门限(45°)关系: EVM=15%% 时相位误差约 8.6°, 裕量充裕\n');
fprintf('  EVM>30%% 说明星座严重扩散, 符号判决将大量出错\n');

function analyze_rx(x, params, rrc, pw, preambleSym, L, tag)
    p = numel(preambleSym);
    mf = conv(x, rrc);
    % 归一化前导相关 (与 frame_detect 同口径)
    corr = abs(filter(flipud(conj(pw)), 1, mf));
    % 归一化: 除以两端能量
    eW = norm(pw);
    % 滑动能量 (简化: 用全局 rms 近似)
    eS = sqrt(mean(abs(mf).^2)) * sqrt(numel(pw));
    rho = corr / (eW * eS + eps);
    [rhoMax, pk] = max(rho);
    fprintf('\n[%s]\n', tag);
    fprintf('  前导相关峰: 位置 %d, 归一化 rho = %.4f (门限 0.60)\n', pk, rhoMax);
    if rhoMax < 0.60
        fprintf('  -> 前导检测不到, 无法评估\n'); return;
    end
    % 前导起点在 mf 中的位置: 峰应对应 pw 末端
    start = pk - numel(pw) + 1;
    idx0 = start + length(rrc) - 1;
    if idx0 <= 0 || idx0 + (params.PreambleSym-1)*L > numel(mf)
        fprintf('  -> 前导起点越界 (%d), 跳过\n', idx0); return;
    end
    rs = mf(idx0:L:idx0 + (p-1)*L);
    rs = rs(:);
    % 去相位
    ph = angle(mean(rs .* conj(preambleSym)));
    z  = rs .* exp(-1j*ph);
    % 归一化到前导理想幅度
    scale = mean(abs(preambleSym));
    sIdeal = preambleSym * scale;
    zN = z;   % 保持真实幅度
    evm = sqrt(mean(abs(zN - sIdeal).^2) / mean(abs(sIdeal).^2)) * 100;
    % 相位误差
    perr = angle(zN .* conj(sIdeal)) * 180/pi;
    fprintf('  |z| 均值 %.4f  标准差 %.4f\n', mean(abs(zN)), std(abs(zN)));
    fprintf('  ★ EVM = %.1f%%   (QPSK 可用门限 ~25-30%%)\n', evm);
    fprintf('  相位误差: 均值 %.1f°  标准差 %.1f°  (P95 |err| = %.1f°)\n', ...
            mean(perr), std(perr), prctile(abs(perr), 95));
    % 隐含 SNR
    snrEst = -20*log10(evm/100);
    fprintf('  隐含链路 SNR ≈ %.1f dB\n', snrEst);
    % 信号功率占用 (饱和判断需知道满量程; 报告原始峰值便于判断)
    fprintf('  接收波形 max %.3f  rms %.3f\n', max(abs(x)), sqrt(mean(abs(x).^2)));
end