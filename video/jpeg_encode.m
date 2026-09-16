function bytes = jpeg_encode(img, quality)
%JPEG_ENCODE  灰度图的 JPEG 编码 (uint8 矩阵 -> uint8 字节流)
%   路线 B: imwrite 经临时文件 (P0 实测 2.47 ms @320x240, 比 Java ImageIO 快 3.4 倍)
%   详见 notes/../博士课程-无线/实验3-P0-环境确认报告.md
%
%   输入:
%     img     : uint8 灰度图 (H x W)
%     quality : JPEG 质量 0~100 (默认 50)
%   输出:
%     bytes   : uint8 列向量 (JPEG 码流)
%
%   说明: 临时文件由 OS 页缓存承载, 磁盘开销可忽略; imwrite/imread 为 MEX 实现。
%         若需避免文件系统 (嵌入式/受限环境), 可改用 Java ImageIO 内存路线,
%         但必须用 BufferedImage(TYPE_INT_RGB) + setRGB,
%         不可用 TYPE_BYTE_GRAY + getRGB (会引入 sRGB 伽马失真, PSNR 仅 13 dB)。

if nargin < 2 || isempty(quality)
    quality = 50;
end

if ~isa(img, 'uint8')
    img = uint8(img);
end
if ndims(img) ~= 2
    error('jpeg_encode:expectsGray', '输入必须是二维灰度图');
end

tmpf = [tempname '.jpg'];
cleanupObj = onCleanup(@() cleanupTmp(tmpf));   %#ok<NASGU>

imwrite(img, tmpf, 'Quality', quality);
fid = fopen(tmpf, 'r');
if fid < 0
    error('jpeg_encode:openFail', '无法打开临时文件 %s', tmpf);
end
bytes = fread(fid, Inf, '*uint8');
fclose(fid);
bytes = bytes(:);

end

function cleanupTmp(f)
    if exist(f, 'file'), delete(f); end
end
