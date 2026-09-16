function content = content_decode(contentType, payloadFrames, meta)
%CONTENT_DECODE  内容源解码: 把多帧 payload 字节还原成内容
%   输入:
%     contentType   : 'text' | 'telemetry' | 'image'
%     payloadFrames : cell 数组, 各帧 payload 字节 (已按帧号排序)
%     meta          : content_encode 返回的元信息 (接收端需要 imgSize 等)
%   输出:
%     content       : 还原的内容 (字符串 / 遥测结构体 / 图像矩阵)

switch lower(contentType)
    case 'text'
        allBytes = cat(1, payloadFrames{:});
        content = char(allBytes(:)).';

    case 'telemetry'
        allBytes = cat(1, payloadFrames{:});
        content = bytes_to_telemetry(allBytes);

    case 'image'
        allBytes = cat(1, payloadFrames{:});
        % 按 meta.imgSize 重塑
        content = reshape(allBytes(1:prod(meta.imgSize)), meta.imgSize);

    otherwise
        error('未知内容类型: %s', contentType);
end

end

%% ===== 局部函数 =====
function tm = bytes_to_telemetry(b)
%BYTES_TO_TELEMETRY  字节流 -> 遥测结构体 (与 telemetry_to_bytes 对应)
b = uint8(b(:));
if length(b) < 26
    tm = struct('error','数据不足');
    return;
end
vals = zeros(1,5);
for i = 1:5
    vals(i) = double(typecast(b((i-1)*4+1:i*4), 'single'));
end
tm.altitude = vals(1);
tm.speed    = vals(2);
tm.pitch    = vals(3);
tm.roll     = vals(4);
tm.yaw      = vals(5);
tm.battery  = b(21);
tm.sats     = b(22);
tm.mode     = char(b(23:26)).';
end
