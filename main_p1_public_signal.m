%% main_p1_public_signal.m
% P1  公网信号接收与频谱特征分析 (保底功能)
%
%   目的: 接收真实公网信号, 展示其频谱特征, 作为课程实验的"参考信道接收"功能。
%         与 P5/P6 的"自建链路"互补 —— 体现"信号采集 + 频谱分析 + 信道特征"能力。
%
%   流程:
%     1. 扫频: 在多个候选公网频点 (GSM900/LTE/WiFi/ADS-B) 各抓 ~500ms, 估功率
%     2. 选最强: 自动定位环境中最强的公网信号
%     3. 长抓: 在最强频点抓 2s IQ
%     4. 全面分析: PSD 频谱 / 时域波形 / 幅度直方图 / IQ 散点 / 占用度
%     5. 报告图保存到 plots/, 数据保存到 results/
%
%   必须在 MATLAB GUI 中运行! (-batch 下 sdrrx 不可用)
%
%   设计参考: notes/ref_matlab_spectral_analysis.md (MathWorks 频谱分析示例)

clear; clc; close all;
addpath('config');

%% ===== 配置 =====
% 候选频点 (Hz) — 选 Pluto 默认范围 (325MHz-3.8GHz) 内的中国公网下行
CFG.candidates = {
    'ADS-B 1090',     1090e6;     % 飞机应答机, 短脉冲
    'GSM900 DL 中段',  940e6;     % 2G 基站, TDMA 突发
    'LTE Band3 DL',   1845e6;     % 4G 中段
    'LTE Band1 DL',   2155e6;     % 4G 主流 (中移动)
    'WiFi ch1',       2412e6;     % 2.4G WiFi
    'WiFi ch6',       2437e6;     % 2.4G WiFi
    'WiFi ch11',      2462e6;     % 2.4G WiFi
};
CFG.SampleRate  = 5e6;     % 5 MHz 瞬时带宽 (覆盖 GSM 单载波 ~200kHz 到 WiFi 20MHz)
CFG.RxGain     = 0;       % 与 P6 一致 (P6a 显示 30dB 频偏最稳)
CFG.scanSec    = 0.5;      % 每个频点扫频时长 (s)
CFG.captureSec = 2.0;      % 选中后长抓时长 (s)
CFG.dryRun     = false;    % ★ 首次建议先改 true 自检
CFG.dryRunMode = 'mixed';  % dryRun 模拟模式: 'lte','gsm','wifi','adsb','mixed'
CFG.lockFc     = 2437e6;       % 若指定 (Hz), 长抓锁在该 fc (默认 []=选最强), 用于跨 gain 对照实验

fprintf('\n################################################################\n');
fprintf('#   P1  公网信号接收与频谱特征分析                              #\n');
fprintf('################################################################\n');
fprintf('  候选频点 %d 个, 扫描时长 %.1f ms/点, 长抓 %.1f s\n', ...
        size(CFG.candidates,1), CFG.scanSec*1000, CFG.captureSec);
fprintf('  采样率 %.1f MHz  接收增益 %d dB\n', CFG.SampleRate/1e6, CFG.RxGain);

%% ===== 1. 扫频找最强频点 =====
fprintf('\n===== 1. 扫频找最强公网信号 =====\n');
scanRes = struct('name',{},'fc',{},'pwrDbm',{},'peakOffsetKHz',{},'occupied',{},'iq',{});
for k = 1:size(CFG.candidates,1)
    name = CFG.candidates{k,1};
    fc   = CFG.candidates{k,2};
    if fc < 325e6 || fc > 3800e6
        fprintf('  [%d] %-18s @ %6.0f MHz : 超出 Pluto 范围, 跳过\n', k, name, fc/1e6);
        continue;
    end
    if CFG.dryRun
        x = simPublicSignal(CFG.candidates, k, CFG.SampleRate, CFG.scanSec, CFG.dryRunMode);
    else
        try
            x = capturePluto(fc, CFG.SampleRate, CFG.RxGain, CFG.scanSec);
        catch e
            fprintf('  [%d] %-18s : 抓取失败: %s\n', k, name, e.message);
            continue;
        end
    end
    % 分析
    pwrDbm = 10*log10(mean(abs(x).^2)+eps) + 30;  % dBFS→dBm 近似 (满量程=0dBm)
    [psd, fAx] = pwelch(x, hanning(2048), 1024, 2048, CFG.SampleRate, 'centered');
    psdDb   = 10*log10(psd+eps);
    [~, idxPk] = max(psd);
    pkOffset = fAx(idxPk);
    noiseFloor = median(psdDb);
    peakPower  = max(psdDb);
    dynamic    = peakPower - noiseFloor;
    occupied   = dynamic > 3;    % ★ 修: OFDM 子载波峰值天然只高 3-7 dB (原 10 dB 漏判 OFDM)
    fprintf('  [%d] %-18s @ %6.0f MHz : 功率 %6.1f dBFS  峰偏 %+6.1f kHz  动态 %5.0f dB  占用=%s\n', ...
            k, name, fc/1e6, pwrDbm-30, pkOffset/1e3, dynamic, tern(occupied,'YES','no '));
    scanRes(end+1).name = name;
    scanRes(end).fc = fc;
    scanRes(end).pwrDbm = pwrDbm;
    scanRes(end).peakOffsetKHz = pkOffset/1e3;   % ★ 修: 转 kHz (字段名暗示 kHz, 但上面写入的是 Hz)
    scanRes(end).occupied = occupied;
    scanRes(end).iq = x;
end

if isempty(scanRes)
    fprintf('\n[!!] 没有捕获到任何信号. 检查天线与频段.\n');  return;
end
[~, bestK] = max([scanRes.pwrDbm]);
best = scanRes(bestK);
fprintf('\n  ★ 最强信号: %s @ %.0f MHz (功率 %.1f dBFS)\n', ...
        best.name, best.fc/1e6, best.pwrDbm-30);

%% ===== 2. 长抓取最强频点 (含细扫对准) =====
fprintf('\n===== 2. 在最强频点长抓 =====\n');
% 2a. 把中心频率微调到扫到的精确峰值位置 (粗扫已显示 peakOffset)
if isempty(CFG.lockFc)
    % 默认: 细扫对准 strongest
    fineFc = best.fc + best.peakOffsetKHz*1e3;
    if fineFc < 325e6 || fineFc > 3800e6
        fineFc = best.fc;   % 边界保护
    end
    fprintf('  2a. 中心频率: %.3f MHz (从粗扫 %.3f MHz 偏移 %+.1f kHz)\n', ...
            fineFc/1e6, best.fc/1e6, best.peakOffsetKHz);
else
    % 用户锁定: 跳过自动选择, 用于跨 gain 对照同一频点
    fineFc = CFG.lockFc;
    fprintf('  2a. ★ 用户锁定长抓 fc = %.3f MHz (跳过自动最强选择)\n', fineFc/1e6);
end
% 2b. 用更宽的带宽, 覆盖整个 WiFi/LTE 信道 (粗扫 5MHz 太窄)
captureFs = max(CFG.SampleRate, 20e6);
fprintf('  2b. 长抓带宽: %.1f MHz (覆盖整个 WiFi 信道)\n', captureFs/1e6);

% 若用户锁定 fc, 覆盖 best, 让图/标题/文件名一致
if ~isempty(CFG.lockFc)
    best.fc   = fineFc;
    best.name = sprintf('LockedFc%.0f', fineFc/1e6);
end

if CFG.dryRun
    xLong = simPublicSignal(CFG.candidates, bestK, captureFs, CFG.captureSec, CFG.dryRunMode);
else
    try
        xLong = capturePluto(fineFc, captureFs, CFG.RxGain, CFG.captureSec);
    catch e
        fprintf('[!!] 长抓失败: %s\n', e.message);  return;
    end
end
fprintf('  采样数 %d (%.3f s)\n', numel(xLong), numel(xLong)/captureFs);

%% ===== 3. 全面分析 =====
fprintf('\n===== 3. 信号分析 =====\n');
fs = captureFs;            % ★ 用长抓带宽 (不是扫频带宽)
N  = numel(xLong);
t  = (0:N-1).'/fs;

% (a) 功率谱密度 (PSD)
[psd, fAx] = pwelch(xLong, hanning(4096), 2048, 4096, fs, 'centered');
psdDb = 10*log10(psd+eps);
noiseFloor = median(psdDb);
peakPower  = max(psdDb);
bw3dB = sum(psdDb > peakPower-3) * (fs/numel(psd)) / 1e3;   % 3dB 带宽 (kHz)
occBW = sum(psdDb > noiseFloor+10) * (fs/numel(psd)) / 1e3;  % 占用带宽 (噪声上10dB, kHz)
fprintf('  噪声底 %.1f dBFS/Hz, 峰值 %.1f dBFS/Hz (动态 %.1f dB)\n', ...
        noiseFloor, peakPower, peakPower-noiseFloor);
fprintf('  3dB 带宽 %.1f kHz, 占用带宽(噪声上10dB) %.1f kHz\n', bw3dB, occBW);

% (b) 时域 + 包络
env = abs(xLong);
envSmooth = movmean(env, 256);
dutyCycle = mean(env > median(env)*1.5);  % "强信号"占比, TDMA/突发类指标

% (b2) ★ ADC 饱和(削顶)检测 —— 硬削顶会把频谱涂抹成假平坦, 必须先排除
%   判据: ① 到达满量程 (Pluto 归一化输出满量程 = 1)
%         ② I 分量在满量程附近"反向堆积" (削顶特征: 尾部不衰减反而抬升)
envMax   = max(abs(xLong));
iAbs     = abs(real(xLong));
d1       = mean(iAbs > 0.95);                 % 满量程附近
d2       = mean(iAbs > 0.85) - d1;            % 次一档
edgeRatio = d1 / max(d2, eps);                % 未饱和 ≈0.3 ; 削顶 ≈2
atFullScale = envMax > 0.98;
clipFrac = mean(abs(xLong) > 0.99*envMax);
isClipped = atFullScale && edgeRatio > 1.2;
if isClipped
    fprintf(2, '  [!!] 检测到 ADC 饱和: 边缘堆积比 %.2f (未饱和约 0.3), 峰值 %.3f, 触顶 %.3f%%\n', ...
            edgeRatio, envMax, clipFrac*100);
    fprintf(2, '       → 谱指标(动态/带宽/占用度)不可信; 请把 CFG.RxGain 降到 0~10 dB 重测\n');
    fprintf(2, '       → 目标: 接收平均功率 <= -12 dBFS, 给 OFDM 的 10~12 dB PAPR 留余量\n');
else
    fprintf('  ADC 未饱和 (边缘堆积比 %.2f, 峰值 %.3f)\n', edgeRatio, envMax);
end

% (c) 频率偏移 (用 PLL 或相位差法)
[ph, ~] = pwelch(xLong, [], [], 2048, fs, 'centered');   % 复用 PSD 看峰值
[~, iPk] = max(ph);
freqOffset = fAx(iPk);

% (d) 占用度 (时间)
% 用短窗分段, 看每段功率, 给出"有信号/无信号"比例
nSeg = 50;
segLen = floor(N/nSeg);
segPwr = zeros(nSeg,1);
for i = 1:nSeg
    s = xLong((i-1)*segLen+1 : i*segLen);
    segPwr(i) = 10*log10(mean(abs(s).^2)+eps);
end
segThr = median(segPwr) + 3;
occupancy = mean(segPwr > segThr) * 100;

fprintf('  频率偏移 %+.1f kHz, 包络占空比 %.1f%%, 时间占用度 %.1f%%\n', ...
        freqOffset/1e3, dutyCycle*100, occupancy);
if isClipped
    fprintf(2, '  ★ 注意: 上述谱指标因饱和而不代表真实信号, 仅功率排名仍有效\n');
end

%% ===== 4. 可视化 =====
fprintf('\n===== 4. 可视化 =====\n');
if ~isfolder('plots'), mkdir('plots'); end
f = figure('Position',[80 80 1100 760],'Color','w');

% (1) 扫频柱状图
subplot(3,2,1);
bar([scanRes.pwrDbm]-30, 'FaceColor',[0.2 0.6 0.8]);
grid on; ylabel('功率 (dBFS)');
xticks(1:numel(scanRes)); xticklabels({scanRes.name}); xtickangle(30);
title(sprintf('公网频点扫描 (采样率 %.1f MHz, 扫描 %.0f ms/点)', fs/1e6, CFG.scanSec*1000));
hold on; plot(bestK, scanRes(bestK).pwrDbm-30, 'rv', 'MarkerSize', 14, 'LineWidth', 2);
legend('功率','最强', 'Location','northwest');

% (2) PSD 频谱
subplot(3,2,2);
plot(fAx/1e3, psdDb, 'b', 'LineWidth', 0.7); grid on;
xlabel('频率偏移 (kHz)'); ylabel('PSD (dBFS/Hz)');
title(sprintf('最强信号 PSD: %s @ %.0f MHz (噪声底 %.0f, 动态 %.0f dB)', ...
        best.name, best.fc/1e6, noiseFloor, peakPower-noiseFloor));
xlim([-fs/2 fs/2]/1e3);

% (3) 时域波形 (前 5ms)
subplot(3,2,3);
nShow = min(floor(fs*5e-3), N);
plot(t(1:nShow)*1e3, real(xLong(1:nShow)), 'b'); hold on;
plot(t(1:nShow)*1e3, envSmooth(1:nShow), 'r', 'LineWidth', 1.5);
grid on; xlabel('时间 (ms)'); ylabel('幅度');
title(sprintf('时域波形 (前 5ms): 实部 + 包络'));
legend('I 路','包络', 'Location','northeast');

% (4) 包络直方图
subplot(3,2,4);
histogram(env, 50, 'Normalization', 'pdf');
hold on; grid on;
x = linspace(0, max(env)*1.1, 200);
sigma = std(xLong);
plot(x, exp(-x.^2/(2*sigma^2))/(sigma*sqrt(2*pi)), 'r', 'LineWidth', 1.5);
xlabel('|x|'); ylabel('概率密度');
title(sprintf('包络分布 (实线: 理论 Rayleigh, σ=%.3f)', sigma));
legend('实测', 'Rayleigh', 'Location','northeast');

% (5) IQ 散点
subplot(3,2,5);
nDec = 20;
plot(real(xLong(1:nDec:end)), imag(xLong(1:nDec:end)), '.', 'MarkerSize', 1);
axis equal; grid on; xlabel('I'); ylabel('Q');
title('IQ 散点 (降采样 20:1)');

% (6) 短时分段功率 (占用度可视化)
subplot(3,2,6);
bar(segPwr, 'FaceColor',[0.4 0.7 0.4]);
hold on; yline(segThr, 'r--', sprintf('阈值 %.1f dBFS', segThr), 'FontSize', 8);
grid on; xlabel('时间分段 (n=50)'); ylabel('功率 (dBFS)');
title(sprintf('短时功率 (%.0f ms/段) - 时间占用度 %.0f%%', ...
        (segLen/fs)*1000, occupancy));

sgtitle(sprintf('P1 公网信号接收: %s @ %.0f MHz | RxGain=%d dB | 采样率 %.1f MHz', ...
        best.name, best.fc/1e6, CFG.RxGain, fs/1e6), 'FontSize', 12);

fn = fullfile('plots', sprintf('p1_public_signal_%s.png', best.name(1:min(8,end))));
saveas(f, fn);
fprintf('  [OK] 图已保存 %s\n', fn);

%% ===== 5. 保存数据 + 汇总 =====
if ~isfolder('results'), mkdir('results'); end
fn = sprintf('results/p1_g%d_%s.mat', round(CFG.RxGain), datestr(now,'yyyymmdd_HHMMSS'));
save(fn, 'CFG', 'scanRes', 'best', 'xLong', 'psd', 'fAx', 'env', ...
     'noiseFloor', 'peakPower', 'bw3dB', 'occBW', 'occupancy', ...
     'clipFrac', 'edgeRatio', 'isClipped', '-v7.3');
fprintf('  [OK] 数据已保存 %s\n', fn);

fprintf('\n################################################################\n');
fprintf('#   P1 完成   (★ 信号特征摘要见上方)                            #\n');
fprintf('################################################################\n');

%% ================= 局部函数 =================
function x = capturePluto(fc, fs, gain, secs)
% 用 sdrrx 抓取 IQ
    rx = sdrrx('Pluto');
    rx.CenterFrequency    = fc;
    rx.BasebandSampleRate = fs;
    rx.SamplesPerFrame    = 8192;
    rx.OutputDataType     = 'double';
    rx.GainSource         = 'Manual';
    rx.Gain               = gain;
    nBlk = ceil(secs*fs/8192);
    x = zeros(nBlk*8192, 1);
    for i = 1:nBlk, x((i-1)*8192+1:i*8192) = rx(); end
    release(rx);
    x = x - mean(x);   % 去直流
end

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end

function x = simPublicSignal(candidates, idx, fs, secs, mode)
% dryRun 模拟: 根据候选频点的"真实信号特性"合成 IQ
%   GSM   - TDMA 突发 (duty ~12.5%)
%   LTE   - 连续 OFDM 宽带
%   WiFi  - beacon 周期 ~100ms
%   ADS-B - 短脉冲 (~120μs)
    n = round(secs*fs);
    t = (0:n-1).'/fs;
    name = candidates{idx,1};
    switch lower(name(1:min(4,end)))
        case 'ads-', kind = 'adsb';
        case {'gsm9','gsm '}, kind = 'gsm';
        case {'lte '}, kind = 'lte';
        case {'wifi'}, kind = 'wifi';
        otherwise,   kind = 'noise';
    end
    if strcmpi(mode, 'noise'), kind = 'noise'; end
    switch kind
        case 'gsm'
            % TDMA 突发 (每 4.615ms 一帧, 占空比 ~12.5%)
            burstPeriod = round(0.004615*fs);
            burstLen    = round(0.000577*fs);
            mask = zeros(n,1);
            for k = 1:burstPeriod:n
                e = min(k+burstLen-1, n);
                mask(k:e) = 1;
            end
            sig = (randn(n,1)+1j*randn(n,1))/sqrt(2) .* mask;
        case 'lte'
            % 连续 OFDM (10 MHz 带宽, 看起来像噪声)
            sig = (randn(n,1)+1j*randn(n,1))/sqrt(2);
            % 加点窄带干扰峰
            sig = sig + 0.5*exp(1j*2*pi*100e3*t);
        case 'wifi'
            % beacon ~100ms 周期, 短突发
            burstPeriod = round(0.1*fs);
            burstLen    = round(2e-3*fs);
            mask = zeros(n,1);
            for k = 1:burstPeriod:n
                e = min(k+burstLen-1, n);
                mask(k:e) = 1;
            end
            sig = (randn(n,1)+1j*randn(n,1))/sqrt(2) .* mask;
        case 'adsb'
            % 短脉冲 ~120μs, 间隔随机
            sig = zeros(n,1);
            nPulse = round(secs/5e-3);    % ~200 个/秒
            for k = 1:nPulse
                center = randi(n);
                dur = randi([round(50e-6*fs), round(120e-6*fs)]);
                idx0 = round(max(1, center-dur/2));
                idx1 = round(min(n, center+dur/2));
                sig(idx0:idx1) = (randn(idx1-idx0+1,1)+1j*randn(idx1-idx0+1,1))/sqrt(2);
            end
        otherwise
            % 纯噪声
            sig = (randn(n,1)+1j*randn(n,1))/sqrt(2);
    end
    x = sig / max(abs(sig)) * 0.7;   % 归一化, 不超过 1
end