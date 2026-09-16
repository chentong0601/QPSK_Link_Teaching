%% main_e4_audio.m
% E4-AUD  语音端到端传输 —— 与视频相反的失效模式
%
%   目的:
%     ① 验证语音 (16 kHz / 8 bit PCM 字节流) 可经链路传输并还原
%     ② 揭示**优雅降级**: 语音丢片只损伤局部 (100 ms), 不像视频丢一片即废整帧
%     ③ 给出丢片率 -> 波形相关 / 分段 SNR 的退化曲线
%
%   素材: content/audio/*.wav   (16 kHz 单声道 8 bit 为目标规格)
%   指标: 波形相关系数 / 分段 SNR / 丢片率 / 实时余量
%
%   用法: matlab -batch "main_e4_audio"
%
%   说明: 全程只用核心 MATLAB + Signal Processing Toolbox (resample),
%         不依赖 Statistics Toolbox (相关系数手算)。

if ~exist('E4_BATCH', 'var')      % 被 main_e4_runall 调用时跳过清理
    clear; clc; close all;
end
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
addpath('video'); addpath('experiments');
params = init_params;
rrc = rcosdesign(params.RollOff, params.RRCSpan, params.SamplesPerSym, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

CFG.dir       = 'content/audio';
CFG.mode      = 'sim';              % ★ 'sim' | 'hw'
CFG.link      = 'sim';              % ★ 'sim' | 'coax' | 'short' | 'long'
CFG.fsTarget  = 16000;              % 目标采样率
CFG.EbN0dB    = 12;
CFG.freqOffset= 320;
CFG.txGain    = -20;
CFG.rxGain    = 30;
% ★ 外部强制覆盖【必须放在所有 CFG 默认值之后】, 否则会被上面的赋值冲掉
if exist('E4_FORCE_MODE', 'var'), CFG.mode = E4_FORCE_MODE; end
if exist('E4_FORCE_LINK', 'var'), CFG.link = E4_FORCE_LINK; end
if exist('E4_FORCE_RXGAIN', 'var') && ~isempty(E4_FORCE_RXGAIN), CFG.rxGain = E4_FORCE_RXGAIN; end
if exist('E4_FORCE_TXGAIN', 'var') && ~isempty(E4_FORCE_TXGAIN), CFG.txGain = E4_FORCE_TXGAIN; end
CFG.dropRates = [0 0.01 0.05 0.10]; % 模拟丢片率对照 (仅 sim 模式; hw 模式自动禁用以省时)
CFG.nSeg      = 20;                 % 分段 SNR 的段数
CFG.blkMs     = 100;                % ★ 音频块长 (ms): 1600 B/块 @16k/8bit → 28 片
if strcmpi(CFG.mode, 'hw')
    CFG.dropRates = 0;              % 硬件模式不做仿真丢片对照
    CFG.hwMaxSec  = 5;              % ★ 硬件模式只取前 N 秒
                                    %   原因: 49 s 音频 → 13552 传输帧 → 波形 16.4M 采样,
                                    %   采集多周期将占用数百 MB 内存 (实测风险)
end

fprintf('\n################################################################\n');
fprintf('#   E4-AUD  语音端到端传输 (优雅降级验证)                          #\n');
fprintf('################################################################\n');

%% ===== 1. 读素材 =====
files = dir(fullfile(CFG.dir, '*.wav'));
files = files(~[files.isdir]);
if isempty(files)
    % 回退: 素材转换产物常放在 content/processed/ 下
    alt = dir(fullfile('content', 'processed', '*.wav'));
    alt = alt(~[alt.isdir]);
    if ~isempty(alt)
        files = alt;
        fprintf('[提示] content/audio/ 无 .wav, 改用 content/processed/ 下的素材\n');
    end
end
if isempty(files)
    fprintf(2, '\n[!] 未找到 .wav 素材 (已查 content/audio/ 与 content/processed/)。\n');
    fprintf(2, '    若素材是 .m4a, 请先转换:\n');
    fprintf(2, '      [y,fs]=audioread(''源.m4a''); audiowrite(''目标.wav'',y,fs);\n');
    return;
end
fp = fullfile(files(1).folder, files(1).name);
[y, fs0] = audioread(fp);
if size(y, 2) > 1, y = mean(y, 2); end          % 立体声 -> 单声道
if fs0 ~= CFG.fsTarget
    y = resample(y, CFG.fsTarget, fs0);          % 重采样 (Signal Processing Toolbox)
end
y = y(:);
% ★ 硬件模式截断 (内存约束: 长音频会产生上万传输帧, 采集时内存占用过大)
if strcmpi(CFG.mode, 'hw') && isfield(CFG, 'hwMaxSec')
    nMax = round(CFG.hwMaxSec * CFG.fsTarget);
    if numel(y) > nMax
        fprintf('[提示] 硬件模式: 音频截取前 %.1f s (原 %.2f s, 受采集内存约束)\n', ...
            CFG.hwMaxSec, numel(y)/CFG.fsTarget);
        y = y(1:nMax);
    end
end
mx = max(abs(y));
if mx > 1e-9, y = y / mx * 0.95; end             % 归一化防削顶

q8 = uint8(round((y + 1) / 2 * 255));            % float -> uint8 (8 bit PCM)
txBytes = uint8(q8);

% ★ 分块: 整段码流远超协议单帧上限 (255 片 = 14790 B), 必须切片后逐块成帧
blkBytes = round(CFG.fsTarget * CFG.blkMs / 1000);      % 每块字节数 (100 ms @16k = 1600 B)
nBlk     = ceil(numel(txBytes) / blkBytes);
txBlocks = cell(1, nBlk);
for b = 1:nBlk
    txBlocks{b} = txBytes((b-1)*blkBytes + 1 : min(b*blkBytes, numel(txBytes)));
end
blkSlices = ceil(blkBytes / 58);

dur = numel(y) / CFG.fsTarget;
fprintf('\n素材: %s\n', files(1).name);
fprintf('  原始采样率 %d Hz -> 目标 %d Hz\n', fs0, CFG.fsTarget);
fprintf('  时长 %.2f s, 单声道, 8 bit PCM, 码流 %d B (%.1f KB)\n', ...
    dur, numel(txBytes), numel(txBytes)/1024);
fprintf('  信道: AWGN (Eb/N0 = %d dB) + 频偏 %d Hz\n', CFG.EbN0dB, CFG.freqOffset);

%% ===== 2. 丢片率对照实验 =====
fprintf('\n===== 丢片率对照 =====\n');
fprintf('%-9s %8s %8s %10s %10s %10s  %s\n', ...
    '丢片率', '片数', '丢片数', '波形相关', '分段SNR(dB)', '传输耗时', '实时余量');

rows = {};
for di = 1:numel(CFG.dropRates)
    opt.EbN0dB = CFG.EbN0dB; opt.freqOffset = CFG.freqOffset;
    opt.verbose = false; opt.dropFrac = CFG.dropRates(di);

    opt.mode = CFG.mode; opt.link = CFG.link; opt.txGain = CFG.txGain; opt.rxGain = CFG.rxGain;
    [rxb, stt] = e4_link(txBlocks, params, rrc, scrambler, opt);   % ★ 分块传入

    if isempty(rxb)
        fprintf('%-9s %8d %8s  接收为空\n', sprintf('%.0f%%', CFG.dropRates(di)*100), stt.nSlices, '-');
        continue;
    end

    rx = (double(rxb(:)) / 255) * 2 - 1;         % 还原为 -1..1
    n  = min(numel(y), numel(rx));

    rho = mcorr(y(1:n), rx(1:n));                % 波形相关系数
    snrSeg = segSNR(y(1:n), rx(1:n), CFG.nSeg);  % 分段 SNR
    realtime = stt.sigDur / dur;                 % <1 = 实时余量

    fprintf('%-9s %8d %8d %10.4f %10.2f %9.2fs   x%.2f\n', ...
        sprintf('%.0f%%', CFG.dropRates(di)*100), stt.nSlices, stt.nDropSim, ...
        rho, snrSeg, stt.sigDur, 1/max(realtime, 1e-9));

    rows(end+1, :) = {CFG.dropRates(di), stt.nSlices, stt.nDropSim, rho, snrSeg, stt.sigDur}; %#ok<SAGROW>
end

%% ===== 3. 无丢片配置: 保存收发音频供试听 =====
% ★ 指标【先】固化, 不依赖后续出图/落盘是否成功
if isempty(rows)
    E4_METRIC = '无有效结果';
else
    E4_METRIC = sprintf('丢片率 %d 档 | 波形相关 %.4f -> %.4f | 分段SNR %.2f -> %.2f dB | %d 块', ...
        size(rows, 1), rows{1,4}, rows{end,4}, rows{1,5}, rows{end,5}, nBlk);
end

opt.dropFrac = 0; opt.verbose = true;
opt.mode = CFG.mode; opt.link = CFG.link; opt.txGain = CFG.txGain; opt.rxGain = CFG.rxGain;
[rxb, stt] = e4_link(txBlocks, params, rrc, scrambler, opt);   % ★ 必须是 txBlocks (分块), 不可用整段
rx0 = (double(rxb(:)) / 255) * 2 - 1;
n0  = min(numel(y), numel(rx0));

outdir = fullfile('results', 'e4', CFG.link);
if ~isfolder(outdir), mkdir(outdir); end
tsTag = datestr(now, 'yyyymmdd_HHMMSS');

fid = sprintf('%s_audio_%s', CFG.link, tsTag);
audiowrite(fullfile(outdir, [fid '_tx.wav']), y(1:n0),   CFG.fsTarget);
audiowrite(fullfile(outdir, [fid '_rx.wav']), rx0(1:n0), CFG.fsTarget);

% ★ 实验条件元数据 (由 main_e4_hw_runall 传入)
antLenCm = NaN; antSepCm = NaN; antOrient = 'parallel';
if exist('E4_FORCE_ANTLEN','var') && ~isempty(E4_FORCE_ANTLEN), antLenCm  = E4_FORCE_ANTLEN; end
if exist('E4_FORCE_ANTSEP','var') && ~isempty(E4_FORCE_ANTSEP), antSepCm  = E4_FORCE_ANTSEP; end
if exist('E4_FORCE_ANTORI','var') && ~isempty(E4_FORCE_ANTORI), antOrient = E4_FORCE_ANTORI; end

cfg = struct('link', CFG.link, 'biz', 'audio', 'mode', CFG.mode, ...
             'centerFreq', params.CenterFrequency, 'sampleRate', params.SampleRate, ...
             'txGain', CFG.txGain, 'rxGain', CFG.rxGain, ...
             'ebn0db', CFG.EbN0dB, 'freqOffset', CFG.freqOffset, ...
             'fsTarget', CFG.fsTarget, 'blkMs', CFG.blkMs, 'nBlk', nBlk, ...
             'antennaLen', antLenCm, 'antSepCm', antSepCm, 'antOrient', antOrient, ...
             'timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
metrics = struct('nSlices', stt.nSlices, 'nFrames', stt.nFrames, ...
                 'rho', mcorr(y(1:n0), rx0(1:n0)), ...
                 'segSNR', segSNR(y(1:n0), rx0(1:n0), CFG.nSeg), ...
                 'nBlk', nBlk, 'blkSlices', blkSlices, 'audioSec', n0/CFG.fsTarget);
if isfield(stt, 'rxPowerDbfs'), metrics.rxPowerDbfs = stt.rxPowerDbfs; end
if isfield(stt, 'freqEstMean'),  metrics.freqEstMean  = stt.freqEstMean;  end
raw = struct('txAudio', y(1:n0), 'rxAudio', rx0(1:n0), 'fs', CFG.fsTarget);

% ★ 出图: 语音传输对比图 (纯 MATLAB 实现, 见 experiments/e4_plot_audio.m)
try
    e4_plot_audio(CFG.link, y(1:n0), rx0(1:n0), CFG.fsTarget, metrics);
catch ME
    fprintf(2, '\n[!!] 语音对比图生成失败: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf(2, '     出错位置: %s (行 %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

save(fullfile(outdir, [fid '.mat']), 'cfg', 'metrics', 'raw', 'rows', 'stt', '-v7.3');
fprintf('[OK] 结果已存 results/e4/%s/%s.mat (+ tx/rx.wav)\n', CFG.link, fid);

fprintf('\n===== 无丢片结果 =====\n');
fprintf('  波形相关系数 : %.4f\n', mcorr(y(1:n0), rx0(1:n0)));
fprintf('  分段 SNR     : %.2f dB\n', segSNR(y(1:n0), rx0(1:n0), CFG.nSeg));
fprintf('  [OK] 收发音频已存 results/e4_audio/ (可试听对比)\n');

%% ===== 4. 退化曲线 =====
if size(rows, 1) >= 2
    f = figure('Position', [80 80 800 380], 'Color', 'w');
    dr = cell2mat(rows(:, 1)) * 100;
    subplot(1,2,1);
    plot(dr, cell2mat(rows(:, 4)), '-o', 'LineWidth', 1.5);
    grid on; xlabel('丢片率 (%)'); ylabel('波形相关系数');
    title('波形相关 vs 丢片率'); ylim([0 1.05]);
    subplot(1,2,2);
    plot(dr, cell2mat(rows(:, 5)), '-s', 'LineWidth', 1.5);
    grid on; xlabel('丢片率 (%)'); ylabel('分段 SNR (dB)');
    title('分段 SNR vs 丢片率');
    sgtitle('E4-AUD 语音链路退化曲线 (优雅降级)', 'FontSize', 12);
    if ~isfolder('plots'), mkdir('plots'); end
    if ~isfolder(fullfile('plots','e4')), mkdir(fullfile('plots','e4')); end
    % ★ 文件名必须含 link, 否则换链路重跑会覆盖
    saveas(f, fullfile('plots', 'e4', sprintf('%s_audio_curve.png', CFG.link)));
    fprintf('  [OK] 退化曲线 plots/e4_audio.png\n');
end

fprintf('\n  结论: 语音在丢片率上升时性能**平滑退化** (对比视频的"全有或全无")\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function r = mcorr(a, b)
%MCORR  归一化互相关系数 (不依赖 Statistics Toolbox)
    a = double(a(:)) - mean(a);
    b = double(b(:)) - mean(b);
    d = sqrt(sum(a.^2) * sum(b.^2));
    if d < 1e-12, r = NaN; else, r = sum(a .* b) / d; end
end

function v = segSNR(ref, test, nSeg)
%SEGSNR  分段信噪比 (dB): 逐段计算后取中位数, 抗个别段异常
    L = numel(ref);
    segLen = floor(L / nSeg);
    if segLen < 1, v = NaN; return; end
    vals = nan(1, nSeg);
    for i = 1:nSeg
        idx = (i-1)*segLen + (1:segLen);
        e = ref(idx) - test(idx);
        pe = sum(e.^2);
        ps = sum(ref(idx).^2);
        if pe < 1e-12
            vals(i) = 60;                       % 该段无误差, 记上限
        else
            vals(i) = 10*log10(ps / pe);
        end
    end
    v = median(vals(~isnan(vals)));
end
