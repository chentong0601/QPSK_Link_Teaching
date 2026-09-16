function rxBits = rx_baseband(rxWave, L, rrc, numSym, bitsPerSym, M)
%RX_BASEBAND  接收机基带处理: 匹配滤波 + 下采样 + 判决 + 解码
%   输入:
%     rxWave    : 接收到的基带波形 (复, 长度 = 发射波形长度)
%     L         : 每符号采样数 (SamplesPerSym, 必须与发端一致)
%     rrc       : RRC 滤波器 (与发端同一个, 匹配滤波)
%     numSym    : 期望还原的符号数
%     bitsPerSym: 每符号比特数 (= log2(M), QPSK=2)
%     M         : 星座大小 (=4)
%   输出:
%     rxBits    : 判决并解码出的比特列向量 (长度 = numSym*bitsPerSym)
%
%   链路位置: 信道 → [本函数: 匹配滤波→下采样→判决→解码] → 与发端比特比错
%
%   关键点1(匹配滤波): 对白噪声信道, 使抽样点 SNR 最大的接收滤波器 = 发送
%     脉冲的时间反转; 因 RRC 实偶对称, 时间反转 = 自身, 所以直接用 rrc 卷积。
%   关键点2(抽样位置): 双 RRC 级联的峰值相对上采样点偏移 = length(rrc)。
%     推导: 单次卷积峰值在 i + (rrc_center-1), 中心索引 rrc_center=(Nf+1)/2;
%           两次卷积总偏移 = 2*(Nf-1)/2 = Nf-1, 再 +1 到峰值起点 = Nf。
%     (详细验证见 experiments/diag_stage2_understand7.m)
%     抽样点每隔 L 取一个, 这些位置恰好是升余弦(RC)过零点, 无码间串扰。

% --- 匹配滤波 (第二次用 rrc 卷积, 收发级联成完整升余弦 RC) ---
mfOut = conv(rxWave, rrc);

% --- 下采样: 从峰值起点起, 每隔 L 点取一个, 共 numSym 个 ---
peak   = length(rrc);                    % 峰值偏移 = 滤波器长度
rxSym  = mfOut(peak : L : peak + (numSym-1)*L);   % numSym x 1 还原符号

% --- 判决: 每个复点判到最近的理想星座点 (最近邻准则, 同阶段1) ---
ref     = pskmod((0:M-1).', M);          % 理想 QPSK 星座点
dist2   = abs(rxSym.' - ref).^2;         % M x numSym
[~, mi] = min(dist2, [], 1);             % 每列最近参考点的行号
symIdx  = (mi - 1).';                    % 行号1..M -> 符号索引 0..M-1

% --- 解码回比特 (行展平, 与发端 dataBits 顺序一致) ---
bitMat  = de2bi(symIdx, bitsPerSym, 'left-msb');
rxBits  = reshape(bitMat.', [], 1);

end
