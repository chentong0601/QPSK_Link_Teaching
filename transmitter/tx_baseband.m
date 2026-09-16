function [txWave, upsampled] = tx_baseband(symbols, L, rrc)
%TX_BASEBAND  发射机基带处理: 上采样 + RRC 脉冲成形
%   输入:
%     symbols : N x 1 复符号列向量 (QPSK 星座点, 单位幅度)
%     L       : 每符号采样数 (SamplesPerSym)
%     rrc     : RRC 成形滤波器系数 (长度 = RRCSpan*L+1, 收发共用同一滤波器)
%   输出:
%     txWave   : 成形后的基带波形, 长度 = N*L + length(rrc) - 1
%                (比 N*L 多出滤波器建立/拖尾, 两端的瞬态在真实系统中
%                 由接收端帧同步/丢弃保护段处理, 本仿真忽略其影响)
%     upsampled: 上采样后的稀疏序列 (调试用, 可选)
%
%   链路位置: 比特→QPSK调制(在主脚本)→[本函数: 上采样→RRC成形]→ 信道
%   说明: 与 rx_baseband 成对使用。收发必须用同一 rrc 参数(β, span, L)。

upsampled = zeros(length(symbols) * L, 1);
upsampled(1 : L : end) = symbols;      % 每隔 L 格放一个符号, 其余填 0

txWave = conv(upsampled, rrc);         % 卷积 = 每个符号"铺开"成一条 RRC 脉冲

end
