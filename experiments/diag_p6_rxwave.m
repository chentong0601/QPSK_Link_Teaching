%experiments/diag_p6_rxwave.m  真实空口接收波形质量分析
%  数据: results/p6_link_*.mat 中 P6a 保存的 rxData (各 RxGain 一份)
%  目的: 判断 P6b 图像 PSNR 17dB 的根因
%        - ADC 饱和/削顶 (RxGain 过高)?
%        - 星座点扩散 (信噪比不足)?
%        - 非线性失真 (星座点压缩)?
%  用法: matlab -batch "addpath('experiments'); diag_p6_rxwave"

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params; L = params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[preambleSym, ~, ~, ~] = frame_sequences_cached(params);
Nsym = params.PreambleSym + params.HeaderSym + params.PayloadSym;

% 找到最新的 P6a 结果
d = dir('results/p6_link_*.mat');
[~, idx] = max([d.datenum]);
fn = fullfile(d(idx).folder, d(idx).name);
fprintf('读取 %s\n\n', fn);
S = load(fn);

nG = numel(S.res);
for g = 1:nG
    rxd = S.res(g).rxData;
    if isempty(rxd), continue; end
    rxd = rxd(:);
    a = abs(rxd);

    fprintf('===== RxGain = %d dB =====\n', S.res(g).gain);
    fprintf('  采样数 %d (%.3f s)\n', numel(rxd), numel(rxd)/params.SampleRate);
    fprintf('  幅度: max %.4f | mean %.4f | rms %.4f | P99 %.4f\n', ...
            max(a), mean(a), sqrt(mean(a.^2)), prctile(a, 99));
    fprintf('  峰均比(PAR) %.2f dB\n', 20*log10(max(a)/sqrt(mean(a.^2))));
    % 削顶检测: Pluto ADC 满量程约 ±1.0 (double 输出); 统计接近 1 的比例
    for thr = [0.5 0.7 0.9 0.95 0.99]
        fprintf('    |x| > %.2f : %.4f%%\n', thr, mean(a > thr)*100);
    end

    % 用前导找一个帧起点, 解调后看星座
    mf = conv(rxd, rrc);
    % 用前导相关找峰
    up = zeros(params.PreambleSym*L,1); up(1:L:end) = preambleSym;
    pw = conv(up, rrc);
    corr = abs(filter(flipud(conj(pw)), 1, mf)) / (norm(pw)*norm(mf(1:min(numel(mf),numel(pw))))+eps);
    [~, pk] = max(corr);
    fprintf('  前导相关峰位置 %d, 峰值 %.4f\n', pk, corr(pk));

    % 按峰对齐, 取一段符号看星座
    start = pk - numel(pw) + 1 + 1;   % mf 中前导起点
    idx0 = start + length(rrc) - 1;    % 抽样相位
    if idx0 > 0 && idx0 + (params.PreambleSym-1)*L <= numel(mf)
        rs = mf(idx0:L:idx0 + (params.PreambleSym-1)*L);
        % 去相位 (用前导)
        ph = angle(mean(rs(:).*conj(preambleSym(:))));
        z  = rs(:).*exp(-1j*ph);
        % 归一化到单位圆, 计算 EVM (QPSK)
        zN = z ./ mean(abs(z));
        ideal = exp(1j*(pi/4 + pi/2*round((angle(zN)-pi/4)/(pi/2))));
        evm = sqrt(mean(abs(zN - ideal).^2)) * 100;
        fprintf('  前导 EVM ≈ %.1f%% (QPSK 理论: <15%% 可用)\n', evm);
        fprintf('  前导 |z| 均值 %.4f, 标准差 %.4f (扩散度)\n', mean(abs(z)), std(abs(z)));
    end
    fprintf('\n');
end

% 星座图
f = figure('Position',[100 100 1100 380],'Color','w');
for g = 1:min(nG,3)
    rxd = S.res(g).rxData(:);
    if isempty(rxd), continue; end
    mf = conv(rxd, rrc);
    up = zeros(params.PreambleSym*L,1); up(1:L:end) = preambleSym;
    pw = conv(up, rrc);
    corr = abs(filter(flipud(conj(pw)), 1, mf));
    [~, pk] = max(corr);
    start = pk - numel(pw) + 1 + 1;
    idx0 = start + length(rrc) - 1;
    if idx0 <= 0 || idx0 + (Nsym-1)*L > numel(mf), continue; end
    rs = mf(idx0:L:idx0 + (Nsym-1)*L);
    ph = angle(mean(rs(1:params.PreambleSym).*conj(preambleSym(:))));
    z = rs.*exp(-1j*ph);
    z = z / mean(abs(z(1:params.PreambleSym)));
    subplot(1,3,g);
    plot(real(z), imag(z), '.', 'MarkerSize', 4); hold on;
    th = linspace(0,2*pi,100);
    plot(cos(th), sin(th), 'r--', 'LineWidth', 0.5);
    axis equal; grid on; xlim([-2 2]); ylim([-2 2]);
    title(sprintf('RxGain=%d dB', S.res(g).gain), 'FontSize', 10);
end
sgtitle('P6a 真实空口接收星座图 (前导+帧头+载荷)', 'FontSize', 11);
saveas(f, 'plots/diag_p6_rxwave_constellation.png');
fprintf('[OK] 星座图已保存 plots/diag_p6_rxwave_constellation.png\n');