function [preambleBits, scrambler, preambleSym] = gen_frame_sequences(params)
%GEN_FRAME_SEQUENCES  生成收发共享的帧序列 (前导比特 + 扰码)
%   收发两端调用此函数得到完全一致的序列 (真实工程中写死为常量表)
%   输出:
%     preambleBits: 前导比特列向量 (PreambleSym*bitsPerSym x 1)
%     scrambler   : 扰码比特列向量 (PayloadSym*bitsPerSym x 1)
%     preambleSym : 前导 QPSK 符号 (PreambleSym x 1)
%
%   设计说明:
%     1. 用固定种子 rng(42) => 无论谁调用、调用多少次, 序列都确定
%     2. 前导要求: 伪随机(自相关尖锐) + 合法QPSK点 => 随机比特再调制
%     3. 扰码要求: 与payload等长, 伪随机 => 频谱均匀

M          = params.M;
bitsPerSym = params.bitsPerSym;

% --- 固定种子, 保证收发一致 ---
rng(42);

% 前导比特: 数量 = 前导符号数 * 每符号比特
preambleBits = randi([0 1], params.PreambleSym * bitsPerSym, 1);

% 扰码: 数量 = payload符号数 * 每符号比特
scrambler = randi([0 1], params.PayloadSym * bitsPerSym, 1);

% 前导 QPSK 符号 (供频偏估计/相关直接用)
preambleIdx = bi2de(reshape(preambleBits, bitsPerSym, []).', 'left-msb');
preambleSym = pskmod(preambleIdx, M);

end
