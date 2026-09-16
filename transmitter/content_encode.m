function [payloadFrames, meta] = content_encode(contentType, params, varargin)
%CONTENT_ENCODE  内容源编码: 把内容切成多帧 payload 字节
%   输入:
%     contentType : 'text' | 'telemetry' | 'image'
%     params      : 参数结构体
%     varargin    : 内容数据
%                    text  -> 字符串
%                    image -> 灰度图像矩阵 (uint8, MxN)
%                    telemetry -> 无(自动生成模拟遥测数据)
%   输出:
%     payloadFrames : cell 数组, 每个元素 = 一帧的 payload 字节 (≤62字节)
%     meta          : 元信息 (类型/总帧数/尺寸等), 供接收端重建
%
%   设计: 每帧 payload 上限 = PayloadSym*bitsPerSym/8 = 62 字节
%         大数据(图像)自动切成多帧, 用帧号区分

maxBytes = params.PayloadSym * params.bitsPerSym / 8;   % 62 字节/帧

switch lower(contentType)
    case 'text'
        str = varargin{1};
        rawBytes = uint8(str(:));
        meta.typeName = 'text';
        meta.textLen  = length(rawBytes);
    case 'telemetry'
        tm = gen_telemetry();
        rawBytes = telemetry_to_bytes(tm);
        meta.typeName = 'telemetry';
        meta.tm = tm;
    case 'image'
        img = varargin{1};
        img = uint8(img);
        meta.typeName = 'image';
        meta.imgSize  = size(img);
        rawBytes = img(:);          % 按列展开
    otherwise
        error('未知内容类型: %s', contentType);
end

% --- 分帧 ---
nFrames = max(1, ceil(length(rawBytes)/maxBytes));
payloadFrames = cell(nFrames, 1);
for i = 1:nFrames
    idx = (i-1)*maxBytes+1 : min(i*maxBytes, length(rawBytes));
    payloadFrames{i} = rawBytes(idx);
end
meta.nFrames = nFrames;
meta.totalBytes = length(rawBytes);

fprintf('[OK] 内容编码: %s, %d 字节, 分 %d 帧\n', meta.typeName, meta.totalBytes, nFrames);

end

%% ===== 局部函数 =====
function tm = gen_telemetry()
%GEN_TELEMETRY  生成一帧模拟无人机遥测数据
tm.altitude = 120.5;      % 高度 m
tm.speed    = 15.3;       % 速度 m/s
tm.pitch    = -2.1;       % 俯仰 度
tm.roll     = 1.5;        % 横滚 度
tm.yaw      = 87.0;       % 偏航 度
tm.battery  = 78;         % 电量 %
tm.sats     = 12;         % GPS 卫星数
tm.mode     = 'AUTO';     % 飞行模式
end

function b = telemetry_to_bytes(tm)
%TELEMETRY_TO_BYTES  遥测结构体 -> 字节流 (简单定长格式, 便于解析)
%   格式: 6个 float(各4字节) + 1个 uint8(电量) + 1个 uint8(卫星) + 4字节模式
vals = [tm.altitude, tm.speed, tm.pitch, tm.roll, tm.yaw];
b = [];
for v = vals
    b = [b; typecast(single(v), 'uint8').'];   %#ok<AGROW>
end
b = [b; uint8(tm.battery); uint8(tm.sats)];
modeBytes = uint8(tm.mode(:));
b = [b; modeBytes(:); zeros(4-length(modeBytes),1)];
end
