function frameSym = tx_frame(payloadBytes, params, frameType, frameNum)
%TX_FRAME  组帧: 把 payload 字节封装成完整帧符号流
%   输入:
%     payloadBytes : 列向量 uint8/int8, 待发送的数据 (长度 ≤ 62 字节)
%     params       : 参数结构体 (init_params)
%     frameType    : 帧类型 0~3 (0=文字 1=遥测 2=图像 3=保留)
%     frameNum     : 帧号 0~255
%   输出:
%     frameSym     : 完整帧 QPSK 符号流 = [前导(32) | 帧头(16) | payload(≤248)]
%
%   帧格式 (见 notes/design.md §3):
%     | 前导(32符号, 伪随机已知) | 帧头(16符号=32bit) | payload(≤248符号=62字节) |
%   帧头 32 bit: 类型(2) | payload字节数(8) | 帧号(8) | 校验(8) | 保留(6)
%   - 校验 = payload 字节数 mod 256 (极简, 用于演示帧头校验概念)
%   - payload 不足 62 字节时, 末尾自动补 0 (接收端按帧头长度截断)

M          = params.M;
bitsPerSym = params.bitsPerSym;

%% ---- 1. 生成共享帧序列 (前导 + 扰码, 与接收端完全一致) ----
[preambleSym, scrambler] = frame_sequences_cached(params);
% 注: 用缓存版本 —— 原实现每帧调用 gen_frame_sequences (内含 rng(42) 重置)
%     并重建序列, 实测占发射端单帧耗时的大部分 (476 帧共 1.23 s, 合 2.6 ms/帧)
% 注: 前导伪随机 => 自相关尖锐; 扰码 XOR => 频谱均匀 (见 design.md §3)

%% ---- 2. 生成帧头符号 (32 bit) ----
% 真实有效载荷字节数 (接收端据此截断填充)
if length(payloadBytes) > params.PayloadSym * bitsPerSym / 8
    error('payload 过长: %d 字节 > 上限 %d', length(payloadBytes), ...
          params.PayloadSym * bitsPerSym / 8);
end
nBytes = length(payloadBytes);                       % 有效字节数
chk    = mod(nBytes, 256);                           % 简单校验 (演示用)

hdrParts = [de2bi(frameType, params.FrameType.Bits, 'left-msb'), ...  % 2
            de2bi(nBytes,    params.FrameLen.Bits,  'left-msb'), ...  % 8
            de2bi(frameNum,   params.FrameNum.Bits,  'left-msb'), ...  % 8
            de2bi(chk,        params.FrameChk.Bits,  'left-msb'), ...  % 8
            zeros(1, params.FrameRsv.Bits)];                          % 6
headerBits = hdrParts.';
headerBits = headerBits(:);                        % 32 x 1
symIdxHeader = bi2de(reshape(headerBits, bitsPerSym, []).', 'left-msb');
headerSym    = pskmod(symIdxHeader, M);            % 16 符号

%% ---- 3. payload: 字节 -> 比特 -> 加扰 -> QPSK 符号 (不足补 0) ----
% 加扰: 把数据的 0/1 长串打散为伪随机模式 (工程标准做法)
%   - 避免长串的 0/1 导致成形后频谱窄、波形不活跃
%   - 提高接收端滑动相关的旁瓣表现 (W2 帧检测更稳定)
%   收发双方预置同一扰码序列 (来自 gen_frame_sequences); 接收端 XOR 即可还原
% 统一转 uint8 再转比特 (de2bi 对 0~255 稳定)
payloadBytes = uint8(payloadBytes(:));
nPadBits = params.PayloadSym * bitsPerSym - length(payloadBytes) * 8;
padBits  = zeros(nPadBits, 1);                     % 自动补 0 至满帧
byteBits = reshape(de2bi(double(payloadBytes), 8, 'left-msb').', [], 1);
payloadBits = xor([byteBits; padBits], scrambler); % 加扰 (异或)

symIdxPayload = bi2de(reshape(payloadBits, bitsPerSym, []).', 'left-msb');
payloadSym    = pskmod(symIdxPayload, M);

%% ---- 4. 拼接完整帧 ----
frameSym = [preambleSym; headerSym; payloadSym];

end
