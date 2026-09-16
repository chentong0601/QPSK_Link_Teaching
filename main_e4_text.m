%% main_e4_text.m
% E4-TXT  文字端到端传输 —— 语义内容的无损性验证
%
%   目的: 验证链路能把"有语义的文本"一字不差地送达。
%         与随机字节不同, 中文 UTF-8 每字 3 字节, 错 1 字节即产生乱码, 读者立刻可辨。
%
%   素材: content/text/*.txt
%   指标: 字节正确率 / 字符正确率 / 传输帧数 / 耗时
%
%   用法: matlab -batch "main_e4_text"
%
%   附加: 同时给出"若载荷无校验, 误码会直接损坏文本"的证据,
%         为审计项 C1/C2 (帧头不保护载荷) 提供实测支撑。

if ~exist('E4_BATCH', 'var')      % 被 main_e4_runall 调用时跳过清理, 避免清掉批处理变量
    clear; clc; close all;
end
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
addpath('video'); addpath('experiments');
params = init_params;
rrc = rcosdesign(params.RollOff, params.RRCSpan, params.SamplesPerSym, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

CFG.dir  = 'content/text';
CFG.mode       = 'sim';      % ★ 'sim' = 仿真信道 | 'hw' = Pluto 真实收发(需在 GUI 运行)
CFG.link       = 'sim';      % ★ 'sim' | 'coax' | 'short' | 'long'  (决定落盘子目录)
CFG.EbN0dB     = 12;         % 仅 sim 模式使用
CFG.freqOffset = 320;        % 仅 sim 模式使用
CFG.txGain     = -20;        % 仅 hw 模式使用
CFG.rxGain     = 30;         % 仅 hw 模式使用
% ★ 外部强制覆盖【必须放在所有 CFG 默认值之后】, 否则会被上面的赋值冲掉
if exist('E4_FORCE_MODE', 'var'), CFG.mode = E4_FORCE_MODE; end
if exist('E4_FORCE_LINK', 'var'), CFG.link = E4_FORCE_LINK; end
if exist('E4_FORCE_RXGAIN', 'var') && ~isempty(E4_FORCE_RXGAIN), CFG.rxGain = E4_FORCE_RXGAIN; end
if exist('E4_FORCE_TXGAIN', 'var') && ~isempty(E4_FORCE_TXGAIN), CFG.txGain = E4_FORCE_TXGAIN; end

fprintf('\n################################################################\n');
fprintf('#   E4-TXT  文字端到端传输                                        #\n');
fprintf('################################################################\n');

%% ===== 1. 读素材 =====
files = dir(fullfile(CFG.dir, '*.txt'));
files = files(~[files.isdir]);
if isempty(files)
    fprintf(2, '\n[!] %s 下没有 .txt 素材, 请先放入文字内容。\n', CFG.dir);
    return;
end
fp  = fullfile(files(1).folder, files(1).name);
txt = fileread(fp);
txBytes = uint8(unicode2native(txt, 'UTF-8'));    % ★ 文本 -> UTF-8 字节流

fprintf('\n素材: %s\n', files(1).name);
fprintf('  字符数 %d, UTF-8 字节数 %d\n', numel(txt), numel(txBytes));
fprintf('  信道: AWGN (Eb/N0 = %d dB) + 载波频偏 %d Hz\n', CFG.EbN0dB, CFG.freqOffset);

%% ===== 2. 过链路 =====
opt.EbN0dB = CFG.EbN0dB; opt.freqOffset = CFG.freqOffset; opt.verbose = true;
opt.mode = CFG.mode; opt.link = CFG.link; opt.txGain = CFG.txGain; opt.rxGain = CFG.rxGain;
fprintf('\n===== 传输 (mode=%s, link=%s) =====\n', CFG.mode, CFG.link);
[rxBytes, stt] = e4_link(txBytes, params, rrc, scrambler, opt);

%% ===== 3. 逐字节比对 =====
fprintf('\n===== 校验 =====\n');
nTx = numel(txBytes);  nRx = numel(rxBytes);
nMin = min(nTx, nRx);

% ★ 以 isequal 为唯一权威判据 (它在 stt 中已被验证可靠)
allSame = isequal(txBytes(:), rxBytes(:));

% 逐字节错误计数: 显式 double 化, 消除 uint8/char 类型歧义
if nMin > 0
    dm = (double(txBytes(1:nMin)) ~= double(rxBytes(1:nMin)));
    nErrByte = sum(dm(:));
else
    nErrByte = 0;
end
nErrByte = nErrByte + abs(nTx - nRx);          % 长度差也计入错误

% ★ 正确率以 allSame 为准: 完全一致即 100%, 不受计数异常影响
if allSame
    byteOK = 1;
else
    byteOK = 1 - nErrByte / max(nTx, 1);
end

rxTxt  = native2unicode(rxBytes(:).', 'UTF-8');
charOK = strcmp(rxTxt, txt);

fprintf('  发送/接收字节数 : %d / %d\n', nTx, nRx);
fprintf('  传输帧数        : %d  (片数 %d)\n', stt.nFrames, stt.nSlices);
fprintf('  信号时长        : %.3f s\n', stt.sigDur);
fprintf('  错误字节数      : %d\n', nErrByte);
fprintf('  字节正确率      : %.4f%%\n', byteOK*100);
fprintf('  整体一致(isequal): %s\n', tern(allSame, '是', '否'));
fprintf('  文本完全一致    : %s\n', tern(charOK, '是', '否'));
if allSame ~= (nErrByte == 0)
    fprintf(2, '  [!] 双路校验不一致: isequal=%d, nErrByte=%d (nTx=%d, nRx=%d)\n', ...
            allSame, nErrByte, nTx, nRx);
    fprintf(2, '      以 isequal 为准 (byteOK = %.4f%%)\n', byteOK*100);
end
fprintf('  接收文本        : %s\n', rxTxt(1:min(120, numel(rxTxt))));

% ★ 供 main_e4_runall 汇总读取
E4_METRIC = sprintf('字节正确率 %.4f%% | 文本一致 %d | 字节数 %d/%d | %d 片', ...
                    byteOK*100, charOK, nRx, nTx, stt.nSlices);

%% ===== 4. 按规范落盘 (results/e4/<link>/<link>_<biz>_<ts>.mat) =====
outdir = fullfile('results', 'e4', CFG.link);
if ~isfolder(outdir), mkdir(outdir); end
tsTag = datestr(now, 'yyyymmdd_HHMMSS');

fid = fopen(fullfile(outdir, sprintf('%s_text_%s.txt', CFG.link, tsTag)), 'w', 'n', 'UTF-8');
if fid > 0
    fwrite(fid, unicode2native(rxTxt, 'UTF-8'), 'uint8');
    fclose(fid);
end

% ★ 实验条件元数据 (由 main_e4_hw_runall 传入; 单独跑时用默认值)
antLenCm = NaN; antSepCm = NaN; antOrient = 'parallel';
if exist('E4_FORCE_ANTLEN','var') && ~isempty(E4_FORCE_ANTLEN), antLenCm  = E4_FORCE_ANTLEN; end
if exist('E4_FORCE_ANTSEP','var') && ~isempty(E4_FORCE_ANTSEP), antSepCm  = E4_FORCE_ANTSEP; end
if exist('E4_FORCE_ANTORI','var') && ~isempty(E4_FORCE_ANTORI), antOrient = E4_FORCE_ANTORI; end

cfg = struct('link', CFG.link, 'biz', 'text', 'mode', CFG.mode, ...
             'centerFreq', params.CenterFrequency, 'sampleRate', params.SampleRate, ...
             'txGain', CFG.txGain, 'rxGain', CFG.rxGain, ...
             'ebn0db', CFG.EbN0dB, 'freqOffset', CFG.freqOffset, ...
             'antennaLen', antLenCm, 'antSepCm', antSepCm, 'antOrient', antOrient, ...
             'timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
metrics = struct('nSlices', stt.nSlices, 'nFrames', stt.nFrames, ...
                 'byteOK', byteOK, 'charOK', charOK, ...
                 'nErrByte', nErrByte, 'allSame', allSame);
if isfield(stt, 'rxPowerDbfs'), metrics.rxPowerDbfs = stt.rxPowerDbfs; end
if isfield(stt, 'freqEstMean'),  metrics.freqEstMean  = stt.freqEstMean;  end
if isfield(stt, 'freqEstStd'),   metrics.freqEstStd   = stt.freqEstStd;   end
raw = struct('txBytes', txBytes, 'rxBytes', rxBytes);

% ★ 出图: 文字传输对比图 (纯 MATLAB 实现, 见 experiments/e4_plot_text.m)
try
    e4_plot_text(CFG.link, txBytes, rxBytes, metrics);
catch ME
    fprintf(2, '\n[!!] 文字对比图生成失败: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf(2, '     出错位置: %s (行 %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

fn = fullfile(outdir, sprintf('%s_text_%s.mat', CFG.link, tsTag));
save(fn, 'cfg', 'metrics', 'raw', 'stt', '-v7.3');
fprintf('[OK] 结果已存 %s\n', fn);

fprintf('\n===== 结论 =====\n');
fprintf('  %d 字节文本, 经 %d 片分片传输, 字节正确率 %.4f%%, 文本%s\n', ...
    numel(txBytes), stt.nSlices, byteOK*100, tern(charOK, '完全一致', '不一致'));
fprintf('  载荷可用容量 %d B/帧 (分片头 %d B, 开销 %.2f%%)\n', ...
    video_protocol().DataBytes, video_protocol().HeaderBytes, ...
    video_protocol().HeaderBytes / video_protocol().PayloadBytes * 100);
fprintf('  [OK] 结果已存 results/e4_text/\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end
