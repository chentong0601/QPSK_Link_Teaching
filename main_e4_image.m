%% main_e4_image.m
% E4-IMG  真实图片端到端传输 —— 内容真实性 + 协议边界验证
%
%   目的:
%     ① 用真实照片替代合成测试图, 给出更可信的 PSNR / 压缩率
%     ② 扫描"分辨率 × 质量"组合, 找出**最大可单帧传输的质量**
%     ③ 正面验证协议的 255 片/帧上限 (video_slicer 会直接 error)
%
%   素材: content/image/*.jpg|png  (彩色或灰度均可)
%   指标: PSNR / 压缩率 / 分片数 / 传输帧数 / 耗时 / 是否超协议上限
%
%   用法: matlab -batch "main_e4_image"
%
%   说明: video/jpeg_encode.m 只接受灰度图, 本脚本内联等价的编解码
%         (imwrite/imread) 以支持彩色, 不改动已验证的公共模块。

if ~exist('E4_BATCH', 'var')      % 被 main_e4_runall 调用时跳过清理
    clear; clc; close all;
end
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
addpath('video'); addpath('experiments');
params = init_params;
rrc = rcosdesign(params.RollOff, params.RRCSpan, params.SamplesPerSym, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

CFG.dir        = 'content/image';
CFG.mode       = 'sim';      % ★ 'sim' | 'hw'
CFG.link       = 'sim';      % ★ 'sim' | 'coax' | 'short' | 'long'
CFG.EbN0dB     = 12;
CFG.freqOffset = 320;
CFG.txGain     = -20;
CFG.rxGain     = 30;
% ★ 外部强制覆盖【必须放在所有 CFG 默认值之后】, 否则会被上面的赋值冲掉
if exist('E4_FORCE_MODE', 'var'), CFG.mode = E4_FORCE_MODE; end
if exist('E4_FORCE_LINK', 'var'), CFG.link = E4_FORCE_LINK; end
if exist('E4_FORCE_RXGAIN', 'var') && ~isempty(E4_FORCE_RXGAIN), CFG.rxGain = E4_FORCE_RXGAIN; end
if exist('E4_FORCE_TXGAIN', 'var') && ~isempty(E4_FORCE_TXGAIN), CFG.txGain = E4_FORCE_TXGAIN; end
CFG.sizes      = [160 120; 176 144; 320 240];   % [W H]
CFG.quals      = [50 75 85];
if strcmpi(CFG.mode, 'hw')
    CFG.quals = [50];       % ★ 硬件模式只跑一个质量 (控制收发时长; 仿真模式仍扫全部)
end

P = video_protocol();

fprintf('\n################################################################\n');
fprintf('#   E4-IMG  真实图片端到端传输                                     #\n');
fprintf('################################################################\n');

%% ===== 1. 读素材 =====
files = [dir(fullfile(CFG.dir, '*.jpg')); dir(fullfile(CFG.dir, '*.jpeg'));
         dir(fullfile(CFG.dir, '*.png')); dir(fullfile(CFG.dir, '*.bmp'))];
files = files(~[files.isdir]);
if isempty(files)
    fprintf(2, '\n[!] %s 下没有图片素材。\n', CFG.dir);
    return;
end
fp  = fullfile(files(1).folder, files(1).name);
img0 = imread(fp);
if ~isa(img0, 'uint8'), img0 = uint8(img0); end

fprintf('\n素材: %s\n', files(1).name);
fprintf('  原始尺寸 %d x %d, %d 通道, 宽高比 %.3f\n', ...
    size(img0,1), size(img0,2), size(img0,3), size(img0,2)/size(img0,1));
fprintf('  信道: AWGN (Eb/N0 = %d dB) + 频偏 %d Hz\n', CFG.EbN0dB, CFG.freqOffset);
fprintf('  协议: %d B/帧载荷, 上限 %d 片/帧 (%d B)\n\n', ...
    P.PayloadBytes, P.MaxSlices, P.MaxFrameBytes);

%% ===== 2. 扫描 分辨率 x 质量 =====
fprintf('===== 扫描: 分辨率 x JPEG 质量 =====\n');
fprintf('%-14s %6s %7s %8s %7s  %s\n', '配置', 'Q', '字节', '片数', '超限', '端到端结果');

results = {};
for si = 1:size(CFG.sizes, 1)
    W = CFG.sizes(si, 1); H = CFG.sizes(si, 2);
    imS = letterbox(img0, W, H);          % 等比缩放 + 黑边 (不变形)
    for qi = 1:numel(CFG.quals)
        q = CFG.quals(qi);
        jb = encJpeg(imS, q);
        nSlice = ceil(numel(jb) / P.DataBytes);
        over = nSlice > P.MaxSlices;
        cfg = sprintf('%dx%d', W, H);

        if over
            fprintf('%-14s %6d %7.1f %8d  %5s  跳过 (超协议上限)\n', ...
                cfg, q, numel(jb)/1024, nSlice, '是');
            results(end+1, :) = {cfg, q, numel(jb), nSlice, true, NaN, NaN}; %#ok<SAGROW>
            continue;
        end

        % ---- 过链路 (仿真信道) ----
        opt.EbN0dB = CFG.EbN0dB; opt.freqOffset = CFG.freqOffset; opt.verbose = false;
        opt.mode = CFG.mode; opt.link = CFG.link; opt.txGain = CFG.txGain; opt.rxGain = CFG.rxGain;
        [rxb, stt] = e4_link(jb, params, rrc, scrambler, opt);

        imgRx = [];
        pv = NaN;
        if ~isempty(rxb)
            try
                imgRx = imreadFromBytes(rxb);
                if isequal(size(imgRx), size(imS))
                    pv = psnr8(imS, imgRx);
                end
            catch
            end
        end
        results(end+1, :) = {cfg, q, numel(jb), nSlice, false, stt.ok, pv}; %#ok<SAGROW>

        fprintf('%-14s %6d %7.1f %8d  %5s  %s  PSNR %.2f dB\n', ...
            cfg, q, numel(jb)/1024, nSlice, '否', ...
            tern(stt.ok, '字节一致', '字节不一致'), pv);
    end
end

%% ===== 3. 选最优配置做完整端到端 (含可视化) =====
% 选取 PSNR 最高且单帧可传的配置
best = [];
bestPSNR = -Inf;
for i = 1:size(results, 1)
    if ~results{i, 5} && ~isnan(results{i, 7}) && results{i, 7} > bestPSNR
        bestPSNR = results{i, 7}; best = i;
    end
end

if isempty(best)
    fprintf(2, '\n[!] 没有可用配置。\n'); return;
end

W = str2double(extractBefore(results{best,1}, 'x'));
H = str2double(extractAfter(results{best,1}, 'x'));
q = results{best, 2};
imS = letterbox(img0, W, H);
jb  = encJpeg(imS, q);

opt.verbose = true;
opt.mode = CFG.mode; opt.link = CFG.link; opt.txGain = CFG.txGain; opt.rxGain = CFG.rxGain;
[rxb, stt] = e4_link(jb, params, rrc, scrambler, opt);
imgRx = imreadFromBytes(rxb);

fprintf('\n===== 最优配置端到端 =====\n');
fprintf('  配置        : %dx%d, JPEG Q%d\n', W, H, q);
fprintf('  压缩率      : %.1f : 1  (原始 %d×%d×%d = %.1f KB -> %d B)\n', ...
    (W*H*size(imS,3))/numel(jb), H, W, size(imS,3), W*H*size(imS,3)/1024, numel(jb));
fprintf('  分片/传输帧 : %d 片 / %d 帧\n', stt.nSlices, stt.nFrames);
fprintf('  信号时长    : %.3f s\n', stt.sigDur);
fprintf('  字节一致    : %s\n', tern(stt.ok, '是', '否'));
fprintf('  PSNR        : %.2f dB\n', psnr8(imS, imgRx));

%% ===== 4. 收尾: 先固化指标, 再做(非关键的)出图与落盘 =====
nOver = 0;
for i = 1:size(results, 1), nOver = nOver + results{i, 5}; end   % 统计超限组数

% ★ 关键指标【先】固化: 即使后续出图/落盘异常, 汇总仍能拿到结果
%   (此前 E4_METRIC 放在文件末尾, 一旦中间出错就丢失指标)
E4_METRIC = sprintf('扫描 %d 组 | 最优 %dx%d Q%d PSNR %.2f dB | 超限 %d 组 | 字节一致 %s', ...
    size(results, 1), W, H, q, psnr8(imS, imgRx), nOver, tern(stt.ok, '是', '否'));

% ★ 出图与落盘属非关键步骤, 包在 try 中避免中断主流程
try
    %% ----- 出图 -----
    figure('Position', [80 80 900 420], 'Color', 'w');
    subplot(1,2,1); imshow(imS);  title(sprintf('发送 (%dx%d, Q%d, %d B)', W, H, q, numel(jb)));
    subplot(1,2,2); imshow(imgRx); title(sprintf('接收 (PSNR %.2f dB)', psnr8(imS, imgRx)));
    sgtitle('E4-IMG 真实图片端到端传输', 'FontSize', 12);
    % ★ 与其他业务统一: 输出到 plots/e4/<link>_<biz>.png
    if ~isfolder(fullfile('plots','e4')), mkdir(fullfile('plots','e4')); end
    saveas(gcf, fullfile('plots', 'e4', sprintf('%s_image.png', CFG.link)));

    %% ----- 按规范落盘 -----
    outdir = fullfile('results', 'e4', CFG.link);
    if ~isfolder(outdir), mkdir(outdir); end
    tsTag = datestr(now, 'yyyymmdd_HHMMSS');

    % ★ 实验条件元数据 (由 main_e4_hw_runall 传入)
    antLenCm = NaN; antSepCm = NaN; antOrient = 'parallel';
    if exist('E4_FORCE_ANTLEN','var') && ~isempty(E4_FORCE_ANTLEN), antLenCm  = E4_FORCE_ANTLEN; end
    if exist('E4_FORCE_ANTSEP','var') && ~isempty(E4_FORCE_ANTSEP), antSepCm  = E4_FORCE_ANTSEP; end
    if exist('E4_FORCE_ANTORI','var') && ~isempty(E4_FORCE_ANTORI), antOrient = E4_FORCE_ANTORI; end

    cfg = struct('link', CFG.link, 'biz', 'image', 'mode', CFG.mode, ...
                 'centerFreq', params.CenterFrequency, 'sampleRate', params.SampleRate, ...
                 'txGain', CFG.txGain, 'rxGain', CFG.rxGain, ...
                 'ebn0db', CFG.EbN0dB, 'freqOffset', CFG.freqOffset, ...
                 'antennaLen', antLenCm, 'antSepCm', antSepCm, 'antOrient', antOrient, ...
                 'timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    metrics = struct('nSlices', stt.nSlices, 'nFrames', stt.nFrames, ...
                     'psnr', psnr8(imS, imgRx), 'W', W, 'H', H, 'q', q, ...
                     'bytes', numel(jb), 'nScan', size(results, 1), 'nOver', nOver);
    if isfield(stt, 'rxPowerDbfs'), metrics.rxPowerDbfs = stt.rxPowerDbfs; end
    if isfield(stt, 'freqEstMean'),  metrics.freqEstMean  = stt.freqEstMean;  end
    raw = struct('txImg', imS, 'rxImg', imgRx);

    fn = fullfile(outdir, sprintf('%s_image_%s.mat', CFG.link, tsTag));
    save(fn, 'cfg', 'metrics', 'raw', 'results', 'stt', '-v7.3');
    imwrite(imS,   fullfile(outdir, sprintf('%s_image_%s_tx.png', CFG.link, tsTag)));
    imwrite(imgRx, fullfile(outdir, sprintf('%s_image_%s_rx.png', CFG.link, tsTag)));
    fprintf('[OK] 图 plots/e4_image.png, 数据 %s\n', fn);
catch ME
    fprintf(2, '[!] 出图/落盘异常 (指标已记录, 不影响汇总): %s\n', ME.message);
end

fprintf('     ★ 超出 255 片的配置已被跳过并如实报告 (协议单帧上限)\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function out = letterbox(img, W, H)
%LETTERBOX  等比缩放使图像完整放入 W×H, 余下部分填黑 (不变形)
    [h, w, c] = size(img);
    r = min(W/w, H/h);
    nw = max(1, round(w*r)); nh = max(1, round(h*r));
    small = imresize(img, [nh nw]);
    out = zeros(H, W, c, 'uint8');
    y0 = floor((H-nh)/2); x0 = floor((W-nw)/2);
    out(y0+1:y0+nh, x0+1:x0+nw, :) = small;
end

function bytes = encJpeg(img, quality)
%ENCJPEG  JPEG 编码 (支持灰度与彩色; 等价于 video/jpeg_encode.m 但放宽了通道限制)
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

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end
