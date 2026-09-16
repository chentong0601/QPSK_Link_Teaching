function [payloadBytes, headerInfo, diag] = rx_frame(rxWave, params, scrambler, rrc)
%RX_FRAME  接收一帧: 帧检测 → 频偏补偿 → 解调 → 解扰 → 帧头解析 → payload
%   输入:
%     rxWave   : 接收波形 (采样域, 长度需覆盖整帧)
%     params   : 参数结构体
%     scrambler: 扰码比特 (与 tx_frame 相同, 解扰用)
%     rrc      : RRC 滤波器 (匹配滤波)
%   输出:
%     payloadBytes : 还原的 payload 字节 (按帧头长度截断)
%     headerInfo   : 结构体 {frameType, nBytes, frameNum, crcOK}
%     diag         : 诊断结构体 {frameIdx, freqEst, rxSym, corrPeak, nFrames}
%
%   处理链:
%     rxWave → [帧检测: 前导波形滑动相关] → 切出帧段
%           → [匹配滤波+抽样] → 符号级
%           → [频偏估计: 前导分段相关] → 补偿
%           → [判决] → 比特 → [解扰] → [帧头解析] → payload
%   说明: 与 rx_baseband.m 的区别 = 本函数不假设帧起点已知, 自己找。

M          = params.M;
bitsPerSym = params.bitsPerSym;
L          = params.SamplesPerSym;
NsymTotal  = params.PreambleSym + params.HeaderSym + params.PayloadSym;

%% ---- 0/1. 前导符号与前导成形波形 (带缓存) ----
% 原实现每帧都调用 gen_frame_sequences 重建序列 (其内部含 rng(42) 重置,
% 会反复破坏全局随机数状态) 并重算成形波形。性能剖析实测这两项占单帧
% 耗时的 20.8%, 而它们都是【常量】, 故改用缓存版本 frame_preamble。
[preambleSym, ~, preambleWave] = frame_sequences_cached(params, rrc);

%% ---- 2. 帧检测: 采样域归一化滑动相关找起点 ----
% frame_detect 现在直接返回"帧起点(第1个前导符号的采样位置)"
[frameStart, corrMetric] = frame_detect(rxWave, preambleWave, L);
diag.frameStart = frameStart;
diag.corrMetric = corrMetric;
diag.preambleWave = preambleWave;

if isnan(frameStart)
    error('rx_frame:NoFrame', '未检测到帧 (相关峰低于门限)');
end

%% ---- 3. 切出帧波形 (含前导, 长度覆盖整帧+拖尾) ----
% 最少需要 (NsymTotal-1)*L + 1 个采样才能抽到最后一个符号的最佳点
% (抽样索引 = peak:L:peak+(NsymTotal-1)*L, peak=length(rrc),
%  需 mfOut 长度 ≥ length(rrc)+(NsymTotal-1)*L, 即帧段长 ≥ (NsymTotal-1)*L+1)
minLenNeeded = (NsymTotal-1)*L + 1;
avail = length(rxWave) - frameStart + 1;
if avail < minLenNeeded
    error('rx_frame:Incomplete', ...
          '帧不完整 (可用 %d < 需要 %d 采样), 需继续接收', avail, minLenNeeded);
end
frameLenSamp = min((NsymTotal+1)*L + length(rrc), avail);
rxFrameWave  = rxWave(frameStart : frameStart+frameLenSamp-1);

%% ---- 4. 匹配滤波 + 抽样 (转到符号级, 修正峰值偏移) ----
mfOut = conv(rxFrameWave, rrc);
peak  = length(rrc);
% 帧起点已对准前导起点; 双RRC(成形+匹配)使能量峰出现在 frameStart+length(rrc),
% 故从 mfOut 的第 length(rrc) 个采样起、每隔 L 抽一个即为最佳采样点
rxSymFrame = mfOut(peak : L : peak + (NsymTotal-1)*L);
if length(rxSymFrame) < NsymTotal
    error('rx_frame:Short', '帧段过短, 抽样不足');
end
rxSymFrame = rxSymFrame(1:NsymTotal);

%% ---- 5. 频偏估计 (用前导符号段) + 补偿 ----
preambleSymShort = preambleSym;                % 已知前导(符号级)
[diag.freqEst, rxSymComp] = freq_sync(rxSymFrame, preambleSymShort, L, params.SymbolRate);

%% ---- 5.5 公共相位校正 (关键!) ----
% QPSK 有 4 重相位模糊(0/90/180/270°), 频偏补偿后仍残留常数相位偏移
% (来自 LO 初始相位/信道相位)。必须用已知前导估计并去掉这个常数相位,
% 否则整体旋转会导致判决错误。这是空口 vs 仿真的关键差异。
ph0 = angle(mean(rxSymComp(1:params.PreambleSym) .* conj(preambleSymShort)));
rxSymComp = rxSymComp * exp(-1j*ph0);
diag.phaseOffset = ph0;

%% ---- 6. 判决 ----
% 默认走 DD-PLL 相位跟踪 (W7b); 可用 params.PhaseTrack = false 关闭以对照
usePll = true;
if isfield(params, 'PhaseTrack'), usePll = logical(params.PhaseTrack); end

ref = pskmod((0:M-1).', M);

if usePll
    mu = 0.10;
    if isfield(params, 'PllMu') && ~isempty(params.PllMu), mu = params.PllMu; end
    [symIdxAll, thetaHist, rxTracked] = phase_track(rxSymComp, preambleSymShort, M, mu);
    diag.thetaHist  = thetaHist;
    diag.rxTracked  = rxTracked;
    diag.pllMu      = mu;
else
    dist2     = abs(rxSymComp.' - ref).^2;
    [~, mi]   = min(dist2, [], 1);
    symIdxAll = (mi - 1).';
end

bitMat    = de2bi(symIdxAll, bitsPerSym, 'left-msb');
rxBitsAll = reshape(bitMat.', [], 1);

%% ---- 7. 拆帧: 帧头(32bit) | payload(加扰) ----
nPreambleBits = params.PreambleSym * bitsPerSym;
nHeaderBits   = params.HeaderSym * bitsPerSym;
payloadBitsScr = rxBitsAll(nPreambleBits + nHeaderBits + 1 : end);  % 加扰的payload比特

%% ---- 8. 解扰 (XOR 同一 scrambler) ----
payloadBits = xor(payloadBitsScr, scrambler);

%% ---- 9. 帧头解析 ----
% 帧头 32 bit: type(2) len(8) framenum(8) chk(8) rsv(6)
hdr = rxBitsAll(nPreambleBits+1 : nPreambleBits+nHeaderBits);
o = 1;
hdrType = bi2de(hdr(o:o+1).', 'left-msb');  o = o + params.FrameType.Bits;
hdrLen  = bi2de(hdr(o:o+7).', 'left-msb');  o = o + params.FrameLen.Bits;
hdrNum  = bi2de(hdr(o:o+7).', 'left-msb');  o = o + params.FrameNum.Bits;
hdrChk  = bi2de(hdr(o:o+7).', 'left-msb');  o = o + params.FrameChk.Bits;

headerInfo.frameType = hdrType;
headerInfo.frameNum  = hdrNum;
headerInfo.nBytes    = hdrLen;
headerInfo.crcOK     = (mod(hdrLen,256) == hdrChk);   % 帧头校验

%% ---- 10. 提取 payload 字节 (按帧头 nBytes 截断) ----
nBytes = min(hdrLen, params.PayloadSym*bitsPerSym/8);
byteBits = reshape(payloadBits(1:nBytes*8), 8, []).';
payloadBytes = uint8(bi2de(byteBits, 'left-msb'));

diag.rxSym = rxSymFrame;
diag.rxSymComp = rxSymComp;
end
