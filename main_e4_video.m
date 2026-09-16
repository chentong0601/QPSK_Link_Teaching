%% main_e4_video.m
% E4-VID  真实视频端到端传输 —— 用实拍视频替代合成的"圆盘平移"图案
%
%   目的: 用有真实运动的实拍视频验证链路, 给出更可信的帧率与画质
%   素材: content/video/*.mp4|avi  (建议 4:3, 若为 16:9 会自动等比缩放+补黑边)
%   指标: 帧还原率 / 平均 PSNR / 等效帧率 / 每帧字节数分布
%
%   用法: matlab -batch "main_e4_video"
%
%   说明: 逐帧独立走一次仿真链路 (每帧 = 一个"视频帧"), 接收端按帧号重组。
%         VideoReader 为 MATLAB 核心函数, 无需额外工具箱。

if ~exist('E4_BATCH', 'var')      % 被 main_e4_runall 调用时跳过清理
    clear; clc; close all;
end
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
addpath('video'); addpath('experiments');
params = init_params;
rrc = rcosdesign(params.RollOff, params.RRCSpan, params.SamplesPerSym, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

CFG.dir        = 'content/video';
CFG.mode       = 'sim';    % ★ 'sim' | 'hw'
CFG.link       = 'sim';    % ★ 'sim' | 'coax' | 'short' | 'long'
CFG.W          = 320;      % 目标宽 (4:3)
CFG.H          = 240;      % 目标高
CFG.q          = 50;       % JPEG 质量
CFG.targetFps  = 12;       % 抽帧目标帧率
CFG.maxFrames  = 120;      % 最多处理帧数 (防止过长)
CFG.EbN0dB     = 12;
CFG.freqOffset = 320;
CFG.txGain     = -20;
CFG.rxGain     = 30;
% ★ 外部强制覆盖【必须放在所有 CFG 默认值之后】, 否则会被上面的赋值冲掉
if exist('E4_FORCE_MODE', 'var'), CFG.mode = E4_FORCE_MODE; end
if exist('E4_FORCE_LINK', 'var'), CFG.link = E4_FORCE_LINK; end
if exist('E4_FORCE_RXGAIN', 'var') && ~isempty(E4_FORCE_RXGAIN), CFG.rxGain = E4_FORCE_RXGAIN; end
if exist('E4_FORCE_TXGAIN', 'var') && ~isempty(E4_FORCE_TXGAIN), CFG.txGain = E4_FORCE_TXGAIN; end
if strcmpi(CFG.mode, 'hw')
    CFG.maxFrames = 20;    % ★ 硬件模式限制帧数 (每帧完整收发一次, 控制总时长)
end

P = video_protocol();

fprintf('\n################################################################\n');
fprintf('#   E4-VID  真实视频端到端传输                                     #\n');
fprintf('################################################################\n');

%% ===== 1. 读视频 =====
files = [dir(fullfile(CFG.dir, '*.mp4')); dir(fullfile(CFG.dir, '*.avi'));
         dir(fullfile(CFG.dir, '*.mov'))];
files = files(~[files.isdir]);
if isempty(files)
    fprintf(2, '\n[!] %s 下没有视频素材。\n', CFG.dir);
    return;
end
fp = fullfile(files(1).folder, files(1).name);
vr = VideoReader(fp);
srcW = vr.Width; srcH = vr.Height;
srcFps = vr.FrameRate; srcDur = vr.Duration;

fprintf('\n素材: %s\n', files(1).name);
fprintf('  源规格: %d x %d (宽高比 %.3f), %.2f s, %.1f fps\n', ...
    srcW, srcH, srcW/srcH, srcDur, srcFps);

%% ===== 2. 抽帧 =====
step = max(1, round(srcFps / CFG.targetFps));
frames = {};
k = 0;
while hasFrame(vr) && numel(frames) < CFG.maxFrames
    f = readFrame(vr);
    k = k + 1;
    if mod(k-1, step) == 0
        frames{end+1} = letterbox(f, CFG.W, CFG.H); %#ok<SAGROW>
    end
end
nF = numel(frames);
fprintf('  抽帧: 每 %d 帧取 1, 共 %d 帧 -> %dx%d\n', step, nF, CFG.W, CFG.H);
fprintf('  等效视频时长 %.2f s @ %.1f fps\n', nF/CFG.targetFps, CFG.targetFps);
fprintf('  信道: AWGN (Eb/N0 = %d dB) + 频偏 %d Hz\n', CFG.EbN0dB, CFG.freqOffset);

%% ===== 3. 逐帧传输 =====
fprintf('\n===== 逐帧传输 =====\n');
rxFrames = cell(1, nF);
psnrV    = nan(1, nF);
sliceV   = zeros(1, nF);
byteV    = zeros(1, nF);
okV      = false(1, nF);
sigTotal = 0;

opt.EbN0dB = CFG.EbN0dB; opt.freqOffset = CFG.freqOffset;
opt.verbose = false; opt.dropFrac = 0;

t0 = tic;
for i = 1:nF
    jb  = encJpeg(frames{i}, CFG.q);
    nSl = ceil(numel(jb) / P.DataBytes);
    byteV(i)  = numel(jb);
    sliceV(i) = nSl;

    if nSl > P.MaxSlices
        fprintf('  帧 %2d: %d 片 > 上限 %d, 跳过\n', i, nSl, P.MaxSlices);
        continue;
    end

    opt.mode = CFG.mode; opt.link = CFG.link; opt.txGain = CFG.txGain; opt.rxGain = CFG.rxGain;
    [rxb, stt] = e4_link(jb, params, rrc, scrambler, opt);
    okV(i)      = stt.ok;
    sigTotal    = sigTotal + stt.sigDur;

    if ~isempty(rxb)
        try
            im = imreadFromBytes(rxb);
            if isequal(size(im), size(frames{i}))
                rxFrames{i} = im;
                psnrV(i)    = psnr8(frames{i}, im);
            end
        catch
        end
    end
end
elapsed = toc(t0);

nOK = sum(~isnan(psnrV));
fprintf('  完成 %d 帧, 耗时 %.1f s\n', nF, elapsed);
fprintf('  字节完全一致: %d / %d 帧\n', sum(okV), nF);
fprintf('  可解码并比对: %d / %d 帧\n', nOK, nF);
fprintf('  每帧字节: 均值 %.1f KB, 最大 %.1f KB, 最小 %.1f KB\n', ...
    mean(byteV)/1024, max(byteV)/1024, min(byteV)/1024);
fprintf('  每帧片数: 均值 %.1f, 最大 %d (上限 %d)\n', mean(sliceV), max(sliceV), P.MaxSlices);

%% ===== 4. 端到端指标 =====
fprintf('\n===== 端到端指标 =====\n');
if nOK > 0
    fprintf('  帧还原率      : %.1f%% (%d/%d)\n', nOK/nF*100, nOK, nF);
    fprintf('  平均 PSNR     : %.2f dB (min %.2f, max %.2f)\n', ...
        mean(psnrV(~isnan(psnrV))), min(psnrV(~isnan(psnrV))), max(psnrV(~isnan(psnrV))));
end
fprintf('  信号总时长    : %.2f s\n', sigTotal);
fprintf('  等效端到端帧率: %.1f fps  (帧数 / 信号时长)\n', nOK / max(sigTotal, 1e-9));
fprintf('  处理耗时      : %.1f s (链路占用 %.2f s)\n', elapsed, sigTotal);

%% ===== 5. 可视化 =====
nShow = min(3, nOK);
if nShow > 0
    idx = find(~isnan(psnrV));
    f = figure('Position', [80 80 980 340], 'Color', 'w');
    for j = 1:min(4, numel(idx))
        i = idx(j);
        subplot(2, 4, j);       imshow(frames{i}); title(sprintf('发 %d', i), 'FontSize', 9);
        subplot(2, 4, 4+j);     imshow(rxFrames{i});
        title(sprintf('收 %d (%.1f dB)', i, psnrV(i)), 'FontSize', 9);
    end
    sgtitle(sprintf('E4-VID 真实视频端到端 (%dx%d, Q%d, Eb/N0=%d dB)', ...
        CFG.W, CFG.H, CFG.q, CFG.EbN0dB), 'FontSize', 11);
    if ~isfolder(fullfile('plots','e4')), mkdir(fullfile('plots','e4')); end
    saveas(f, fullfile('plots', 'e4', sprintf('%s_video.png', CFG.link)));
end

%% ===== 6. 收尾: 先固化指标, 再做(非关键的)出图与落盘 =====
% ★ 指标【先】固化, 不依赖后续出图/落盘是否成功
if nOK > 0
    E4_METRIC = sprintf('帧 %d/%d | PSNR %.2f dB | %.1f fps | 每帧 %.1f KB / %.0f 片', ...
        nOK, nF, mean(psnrV(~isnan(psnrV))), nOK/max(sigTotal,1e-9), ...
        mean(byteV)/1024, mean(sliceV));
else
    E4_METRIC = sprintf('帧 %d/%d | 无有效解码', nOK, nF);
end

outdir = fullfile('results', 'e4', CFG.link);
if ~isfolder(outdir), mkdir(outdir); end
tsTag = datestr(now, 'yyyymmdd_HHMMSS');

% ★ 实验条件元数据 (由 main_e4_hw_runall 传入)
antLenCm = NaN; antSepCm = NaN; antOrient = 'parallel';
if exist('E4_FORCE_ANTLEN','var') && ~isempty(E4_FORCE_ANTLEN), antLenCm  = E4_FORCE_ANTLEN; end
if exist('E4_FORCE_ANTSEP','var') && ~isempty(E4_FORCE_ANTSEP), antSepCm  = E4_FORCE_ANTSEP; end
if exist('E4_FORCE_ANTORI','var') && ~isempty(E4_FORCE_ANTORI), antOrient = E4_FORCE_ANTORI; end

cfg = struct('link', CFG.link, 'biz', 'video', 'mode', CFG.mode, ...
             'centerFreq', params.CenterFrequency, 'sampleRate', params.SampleRate, ...
             'txGain', CFG.txGain, 'rxGain', CFG.rxGain, ...
             'ebn0db', CFG.EbN0dB, 'freqOffset', CFG.freqOffset, ...
             'W', CFG.W, 'H', CFG.H, 'q', CFG.q, 'targetFps', CFG.targetFps, ...
             'antennaLen', antLenCm, 'antSepCm', antSepCm, 'antOrient', antOrient, ...
             'timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
metrics = struct('nSlices', sum(sliceV), 'nFrames', nF * mean(sliceV), ...
                 'frameOK', nOK/max(nF,1), 'psnrMean', mean(psnrV(~isnan(psnrV))), ...
                 'fps', nOK/max(sigTotal,1e-9), 'byteMean', mean(byteV), ...
                 'nFrame', nF, 'nOK', nOK, 'sigDur', sigTotal);
if isfield(stt, 'rxPowerDbfs'), metrics.rxPowerDbfs = stt.rxPowerDbfs; end   % 取最后一帧的接收功率
raw = struct('psnrVec', psnrV, 'byteVec', byteV, 'sliceVec', sliceV, 'okVec', okV);

fn = fullfile(outdir, sprintf('%s_video_%s.mat', CFG.link, tsTag));
save(fn, 'cfg', 'metrics', 'raw', 'psnrV', 'byteV', 'sliceV', 'okV', 'sigTotal', '-v7.3');
fprintf('[OK] 结果已存 %s\n', fn);

fprintf('\n[OK] 图 plots/e4_video.png, 数据 results/e4_video/\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function out = letterbox(img, W, H)
%LETTERBOX  等比缩放使图像完整放入 W×H, 余下填黑 (不变形)
    [h, w, c] = size(img);
    r = min(W/w, H/h);
    nw = max(1, round(w*r)); nh = max(1, round(h*r));
    small = imresize(img, [nh nw]);
    out = zeros(H, W, c, 'uint8');
    y0 = floor((H-nh)/2); x0 = floor((W-nw)/2);
    out(y0+1:y0+nh, x0+1:x0+nw, :) = small;
end

function bytes = encJpeg(img, quality)
%ENCJPEG  JPEG 编码 (支持灰度与彩色)
    if ~isa(img, 'uint8'), img = uint8(img); end
    tmpf = [tempname '.jpg'];
    cu = onCleanup(@() rmTmp(tmpf)); %#ok<NASGU>
    imwrite(img, tmpf, 'Quality', quality);
    fid = fopen(tmpf, 'r');
    bytes = fread(fid, Inf, '*uint8');
    fclose(fid);
    bytes = bytes(:);
end

function img = imreadFromBytes(bytes)
%IMREADFROMBYTES  uint8 字节流 -> 图像
    tmpf = [tempname '.jpg'];
    cu = onCleanup(@() rmTmp(tmpf)); %#ok<NASGU>
    fid = fopen(tmpf, 'w');
    fwrite(fid, bytes, 'uint8');
    fclose(fid);
    img = imread(tmpf);
end

function rmTmp(f)
    if exist(f, 'file'), delete(f); end
end

function p = psnr8(a, b)
    a = double(a); b = double(b);
    if ~isequal(size(a), size(b)), p = NaN; return; end
    mse = mean((a(:)-b(:)).^2);
    if mse == 0, p = Inf; else, p = 10*log10(255^2/mse); end
end
