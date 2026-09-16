%% experiments/p0_env_check.m
% P0 环境确认 —— 实验3「构建通信收发机」方案的第一步
% 目的: 在动工前验证全部技术前提, 特别是【方案中的第一个技术风险点:
%       JPEG 内存编解码是否可行、耗时多少】。
%
% 验证项:
%   V1 环境与工具箱
%   V2 ★ Java ImageIO JPEG 内存编解码 可行性与耗时  (核心风险点)
%   V3 视频源可用性 (VideoReader / webcam)
%   V4 通信与 SDR 关键函数可用性
%   V5 PlutoSDR 硬件连接
%   V6 ★ JPEG 压缩率标定 (分辨率 x 质量 -> 字节数 -> 可达帧率)
%
% 用法: matlab -batch "addpath('experiments'); p0_env_check"

clear; clc;
fprintf('\n');
fprintf('################################################################\n');
fprintf('#   P0 环境确认  实验3 构建通信收发机                          #\n');
fprintf('################################################################\n');
fprintf('时间: %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));

%% ===== V1 环境与工具箱 =====
fprintf('\n===== V1 环境与工具箱 =====\n');
v = ver('matlab');
fprintf('MATLAB: %s (%s)\n', v.Release, v.Version);
fprintf('Java  : %s\n', version('-java'));

need = {'Communications Toolbox','DSP System Toolbox','Image Processing Toolbox', ...
        'Instrument Control Toolbox','Signal Processing Toolbox'};
installed = {ver().Name};
for i = 1:numel(need)
    if any(strcmp(installed, need{i}))
        fprintf('  [OK]   %s\n', need{i});
    else
        fprintf('  [MISS] %s\n', need{i});
    end
end
% Support Package 检查
spNames = installed(~cellfun(@isempty, strfind(installed, 'Support Package')));
if isempty(spNames)
    fprintf('  [MISS] 未检测到 Support Package\n');
else
    for i = 1:numel(spNames), fprintf('  [OK]   %s\n', spNames{i}); end
end

%% ===== V2 ★ JPEG 内存编解码 (核心风险点) =====
fprintf('\n===== V2 ★ JPEG 内存编解码 可行性与耗时 =====\n');

img = makeTestImage(240, 320);
fprintf('测试图: %dx%d uint8 灰度\n', size(img,1), size(img,2));

% --- 路径 A: Java ImageIO (内存, 无磁盘往返) ---
okA_enc = false; okA_dec = false; tA_enc = NaN; tA_dec = NaN; nA = NaN;
try
    b = jpegEncodeJava(img, 0.75);
    okA_enc = true; nA = numel(b);
    % 预热
    for i = 1:3, b = jpegEncodeJava(img, 0.75); imgD = jpegDecodeJava(b); end
    N = 30; t0 = tic;
    for i = 1:N, b = jpegEncodeJava(img, 0.75); end
    tA_enc = toc(t0)/N*1000;
    t0 = tic;
    for i = 1:N, imgD = jpegDecodeJava(b); end
    tA_dec = toc(t0)/N*1000;
    okA_dec = true;
    fprintf('[路径A Java ImageIO]  编码 %.2f ms/帧, 解码 %.2f ms/帧, %d 字节\n', ...
            tA_enc, tA_dec, nA);
    fprintf('                     PSNR = %.2f dB\n', psnr8(img, imgD));
catch e
    fprintf('[路径A Java ImageIO]  失败: %s\n', e.message);
end

% --- 路径 B: imwrite/imread 临时文件 (降级备选) ---
okB = false; tB_enc = NaN; tB_dec = NaN;
try
    tmpf = [tempname '.jpg'];
    imwrite(img, tmpf, 'Quality', 75);
    for i = 1:3
        imwrite(img, tmpf, 'Quality', 75);
        imgB = imread(tmpf);
    end
    N = 10; t0 = tic;
    for i = 1:N, imwrite(img, tmpf, 'Quality', 75); end
    tB_enc = toc(t0)/N*1000;
    t0 = tic;
    for i = 1:N, imgB = imread(tmpf); end
    tB_dec = toc(t0)/N*1000;
    okB = true;
    fprintf('[路径B 临时文件]      编码 %.2f ms/帧, 解码 %.2f ms/帧\n', tB_enc, tB_dec);
    fprintf('                     文件系统开销显著 (含磁盘往返)\n');
    delete(tmpf);
catch e
    fprintf('[路径B 临时文件]      失败: %s\n', e.message);
end

% --- 结论 ---
fprintf('\n  >>> V2 结论: ');
if okA_enc && okA_dec
    fprintf('路径A 可用, 单帧编解码合计 %.1f ms (占帧周期 1.184 ms 的 %.0f%%)\n', ...
            tA_enc+tA_dec, (tA_enc+tA_dec)/1.184*100);
    fprintf('      注意: 编解码耗时影响【帧率】而非【单传输帧时延】, 需纳入流水线设计\n');
else
    fprintf('路径A 不可用, 需降级到路径B\n');
end

%% ===== V3 视频源 =====
fprintf('\n===== V3 视频源可用性 =====\n');
fprintf('  VideoReader (核心)     : %s\n', tf(exist('VideoReader','file')==2));
fprintf('  imresize / rgb2gray    : %s\n', tf(exist('imresize','file')==2 && exist('rgb2gray','file')==2));
fprintf('  webcam (USB摄像头支持包): %s\n', tf(exist('webcam','file')==2 || exist('webcam','class')==8));
if exist('webcam','file')~=2 && exist('webcam','class')~=8
    fprintf('      -> 未安装 USB Webcams 支持包; 可改用 VideoReader 读视频文件或合成测试图\n');
end

%% ===== V4 通信与 SDR 函数 =====
fprintf('\n===== V4 关键函数可用性 =====\n');
fns = {'pskmod','pskdemod','rcosdesign','de2bi','bi2de','vitdec','convenc', ...
       'sdrtx','sdrrx','findPlutoRadio','spectrumAnalyzer','pwelch','im2java'};
for i = 1:numel(fns)
    e = exist(fns{i});
    switch e
        case 2, s = '脚本/函数';
        case 5, s = '内建';
        case 6, s = 'MEX';
        case 8, s = '类';
        otherwise, s = '缺失';
    end
    mark = '[OK]  '; if e == 0, mark = '[MISS]'; end
    fprintf('  %s %-18s %s\n', mark, fns{i}, s);
end

%% ===== V5 Pluto 硬件连接 =====
fprintf('\n===== V5 PlutoSDR 硬件连接 =====\n');
try
    r = findPlutoRadio();
    if isempty(r)
        fprintf('  [!!] 未发现 Pluto 设备 (请确认 USB 连接与供电)\n');
    else
        fprintf('  [OK] 发现 %d 台 Pluto:\n', numel(r));
        for i = 1:numel(r)
            fprintf('       RadioID=%s  SerialNum=%s\n', r(i).RadioID, r(i).SerialNum);
        end
    end
catch e
    fprintf('  [!!] findPlutoRadio 执行失败: %s\n', e.message);
    fprintf('       (若在 -batch 模式, Support Package 路径可能未注册, 需在 GUI 中运行)\n');
end

%% ===== V6 ★ JPEG 压缩率标定 =====
fprintf('\n===== V6 ★ JPEG 压缩率标定 (决定可达帧率) =====\n');
fprintf('链路预算: 视频净荷吞吐 ≈ 399 kbps = 49875 字节/s\n');
fprintf('帧率 = 49875 / 单帧字节数\n\n');
if okA_enc
    resList  = [160 120; 176 144; 320 240; 640 480];
    qList    = [0.30 0.50 0.75];
    fprintf('%12s | %8s | %10s | %10s | %10s\n', '分辨率', '质量', '字节/帧', '可达帧率', 'PSNR(dB)');
    fprintf('%s\n', repmat('-', 1, 62));
    for r = 1:size(resList,1)
        im2 = makeTestImage(resList(r,1), resList(r,2));
        for qq = 1:numel(qList)
            b  = jpegEncodeJava(im2, qList(qq));
            nb = numel(b);
            fps = 49875/nb;
            try
                d = jpegDecodeJava(b);
                p = psnr8(im2, d);
                ps = sprintf('%8.2f', p);
            catch
                ps = '     n/a';
            end
            fprintf('%5dx%-6d | %8.2f | %10d | %9.1f  | %s\n', ...
                    resList(r,2), resList(r,1), qList(qq), nb, fps, ps);
        end
    end
else
    fprintf('  (路径A 不可用, 跳过标定)\n');
end

fprintf('\n################################################################\n');
fprintf('#   P0 完成                                                     #\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function img = makeTestImage(h, w)
% 生成有结构的测试图 (含平坦区/渐变/边缘/纹理), 比纯噪声更贴近真实视频
    [X, Y] = meshgrid(linspace(0,1,w), linspace(0,1,h));
    img = uint8(zeros(h, w));
    img = img + uint8(60*X);                                   % 水平渐变
    img = img + uint8(40*sind(8*pi*X) .* cosd(6*pi*Y));        % 低频纹理
    img(X > 0.55 & Y > 0.5) = 210;                             % 亮块
    img(X < 0.3  & Y < 0.35) = 25;                             % 暗块
    img(abs(X-0.5)<0.01) = 255;                                % 竖直边缘
    img = uint8(min(double(img), 255));
end

function s = tf(b)
    if b, s = '可用'; else, s = '不可用'; end
end

function p = psnr8(a, b)
% 8bit 图像的 PSNR
    a = double(a); b = double(b);
    if ~isequal(size(a), size(b))
        p = NaN; return;
    end
    mse = mean((a(:)-b(:)).^2);
    if mse == 0, p = Inf; else, p = 10*log10(255^2/mse); end
end

function bytes = jpegEncodeJava(img, quality)
% JPEG 内存编码: uint8 灰度图 -> uint8 字节流 (Java ImageIO, 无磁盘往返)
    import javax.imageio.ImageIO
    import javax.imageio.ImageWriteParam
    import javax.imageio.IIOImage
    import java.io.ByteArrayOutputStream

    bimg = gray2bimg(img);
    bos  = ByteArrayOutputStream();
    ws   = ImageIO.getImageWritersByFormatName('jpg');
    if ~ws.hasNext(), error('未找到 JPEG 编码器'); end
    wr   = ws.next();
    ios  = ImageIO.createImageOutputStream(bos);
    wr.setOutput(ios);
    pm   = wr.getDefaultWriteParam();
    pm.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
    pm.setCompressionQuality(quality);
    wr.write([], IIOImage(bimg, [], []), pm);
    wr.dispose(); ios.close();
    bytes = typecast(bos.toByteArray(), 'uint8');
    bytes = bytes(:);
end

function img = jpegDecodeJava(bytes)
% JPEG 内存解码: uint8 字节流 -> uint8 灰度图
    import javax.imageio.ImageIO
    import java.io.ByteArrayInputStream
    bimg = ImageIO.read(ByteArrayInputStream(bytes));
    if isempty(bimg), error('JPEG 解码返回空'); end
    w = bimg.getWidth(); h = bimg.getHeight();
    img = zeros(h, w, 'uint8');
    for r = 0:h-1
        row = bimg.getRGB(0, r, w, 1, [], 0, w);   % int[]
        img(r+1, :) = uint8(bitand(bitshift(row, -16), 255));
    end
end

function bimg = gray2bimg(img)
% uint8 灰度矩阵 -> java.awt.image.BufferedImage(TYPE_BYTE_GRAY)
    import java.awt.image.BufferedImage
    [h, w] = size(img);
    bimg = BufferedImage(w, h, BufferedImage.TYPE_BYTE_GRAY);
    raster = bimg.getRaster();
    vals = reshape(img.', 1, []);          % 行优先展开
    raster.setSamples(0, 0, w, h, 1, double(vals));
end
