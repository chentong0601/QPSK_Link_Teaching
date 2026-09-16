function img = jpeg_decode(bytes)
%JPEG_DECODE  JPEG 码流解码为灰度图 (uint8 字节流 -> uint8 矩阵)
%   与 jpeg_encode 配对 (路径 B: imread 经临时文件)
%
%   输入: bytes - uint8 字节流 (JPEG)
%   输出: img   - uint8 灰度图
%
%   错误处理: 码流损坏时 imread 会报错, 调用者应 try/catch 并丢弃该帧

bytes = uint8(bytes(:));

tmpf = [tempname '.jpg'];
cleanupObj = onCleanup(@() cleanupTmp(tmpf));   %#ok<NASGU>

fid = fopen(tmpf, 'w');
if fid < 0
    error('jpeg_decode:openFail', '无法创建临时文件 %s', tmpf);
end
fwrite(fid, bytes, 'uint8');
fclose(fid);

img = imread(tmpf);

% 若解码出彩色(3通道), 转灰度 (正常情况下不会发生)
if ndims(img) == 3
    img = rgb2gray_safe(img);
end

end

function g = rgb2gray_safe(rgb)
    g = uint8(0.2989*double(rgb(:,:,1)) + 0.5870*double(rgb(:,:,2)) + 0.1140*double(rgb(:,:,3)));
end

function cleanupTmp(f)
    if exist(f, 'file'), delete(f); end
end
