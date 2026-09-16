function [payloads, info] = video_slicer(bytes, videoFrameNum)
%VIDEO_SLICER  把一个视频帧 (JPEG 码流) 切分为若干"传输帧载荷"
%   协议见 video_protocol.m
%
%   输入:
%     bytes        : uint8 列向量, 一个视频帧的 JPEG 码流
%     videoFrameNum: 视频帧号 0~255
%   输出:
%     payloads : uint8 (62 x N) 矩阵, 每列是一个传输帧的载荷
%     info     : struct { totalSlices, bytes, overheadRatio }
%
%   用法: 依次把 payloads(:,i) 交给 tx_frame 作为 payloadBytes

P = video_protocol();

bytes = uint8(bytes(:));
n = numel(bytes);

total = max(1, ceil(n / P.DataBytes));
if total > P.MaxSlices
    error('video_slicer:tooLarge', ...
          '视频帧 %d 字节需要 %d 片, 超过上限 %d 片 (%d 字节)。请降低分辨率或提高压缩率。', ...
          n, total, P.MaxSlices, P.MaxFrameBytes);
end

payloads = zeros(P.PayloadBytes, total, 'uint8');

for i = 1:total
    i0 = (i-1)*P.DataBytes + 1;
    i1 = min(i*P.DataBytes, n);
    if i0 > n
        chunk = uint8([]);            % 空片 (理论上不会发生)
    else
        chunk = bytes(i0:i1);
    end
    len = numel(chunk);

    payloads(1, i) = uint8(videoFrameNum);
    payloads(2, i) = uint8(i-1);
    payloads(3, i) = uint8(total);
    payloads(4, i) = uint8(len);
    if len > 0
        payloads(P.HeaderBytes+1 : P.HeaderBytes+len, i) = chunk;
    end
end

info.totalSlices   = total;
info.bytes         = n;
info.overheadRatio = P.HeaderBytes / P.PayloadBytes;

end
