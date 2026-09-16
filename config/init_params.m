function params = init_params()
%INIT_PARAMS  全局参数统一入口 —— QPSK 教学旗舰工程（空口链路版）
%   返回结构体 params，集中管理发射/接收/帧结构/硬件参数。
%
%   本工程定位：把已完成的基带链路(tx_baseband/rx_baseband)接到 Pluto 上
%   做真实空口 QPSK 收发。相比纯仿真，新增两大现实挑战：
%     1) 帧同步（接收端不知道波形从哪开始）→ 前导序列相关峰检测
%     2) 载波频偏（晶振误差使星座旋转）→ 前导辅助频偏估计补偿
%
%   采样率设计说明：
%     本工程硬件模式用 fs = 1 MHz, L = 4（每符号4采样点, 符号率 250 kSps）。
%     理由: Pluto 经 USB2.0 连续收发时，高采样率易溢出丢帧；
%          低采样率利于教学观察和稳定传输。仿真模式可与硬件一致以便无缝衔接。

% ===== 调制 / 符号 =====
params.Modulation   = 'QPSK';
params.M            = 4;
params.bitsPerSym   = log2(params.M);      % 2

% ===== 采样 / 符号率（与 Pluto 硬件一致）=====
params.SamplesPerSym = 4;      % L 每符号采样点 (硬件模式 4, 仿真可另设)
params.SymbolRate    = 250e3;  % Rs 符号率 = 250 kSps
params.SampleRate    = params.SymbolRate * params.SamplesPerSym;  % fs = 1 MHz
params.RollOff       = 0.35;   % RRC 滚降因子
params.RRCSpan       = 6;      % RRC 符号跨度, 滤波器长 = RRCSpan*L+1 = 25

% ===== 帧结构（教学用，简单清晰）=====
params.PreambleSym   = 32;     % 前导符号数（已知伪随机序列, 用于帧检测+频偏估计）
params.HeaderSym     = 16;     % 帧头符号数 (32 bit = 类型2+长度8+帧号8+校验8+保留6)
params.PayloadSym    = 248;    % 数据符号数/帧 (496 bit = 62 字节)
% 帧 = Preamble(32) + Header(16) + Payload(248) = 296 符号
% 注: 前导用伪随机 QPSK 序列（固定种子生成, 收发预置同一份）
% 帧头字段 (32 bit): 类型(2) | payload字节数(8, ≤255) | 帧号(8, 0~255) | 校验(8) | 保留(6)
%   - 长度以字节为单位 => 彻底避免位宽冲突; 帧头校验用于识别帧头损坏
params.HeaderBits     = 32;    % 帧头总位数
params.FrameType.Bits = 2;     % 帧头: 类型
params.FrameLen.Bits  = 8;     % 帧头: payload 字节数 (≤255)
params.FrameNum.Bits  = 8;     % 帧头: 帧号 (0~255 循环)
params.FrameChk.Bits  = 8;     % 帧头: 校验 (payload 字节数按 256 取模, 简单演示)
params.FrameRsv.Bits  = 6;     % 帧头: 保留位

% ===== 仿真用信道参数（L1/L2 层验证，硬件时忽略）=====
params.EbN0dB        = 0:2:10; % BER 扫描范围(仿真层)
params.MaxFreqOffset = 500;    % 仿真注入的最大频偏 Hz（教学演示频偏影响）

% ===== 接收机相位跟踪 (W7b: DD-PLL) =====
% 背景: 频偏估计器的残余误差会在帧内累积成线性相位斜坡 (实测 12 dB 时
%       折合帧内漂移 35.9 度, 逼近 QPSK 45 度判决边界), 导致帧尾大量误码。
%       DD-PLL 用前导定初相 + 逐符号判决导向跟踪, 消除该斜坡。
% 实测: 满载荷 62 字节解帧成功率 12 dB 从 35% 提升到 100%
% 详见 notes/exp_w7_solution_study.md
params.PhaseTrack  = true;   % 是否启用 DD-PLL 相位跟踪 (false 可作对照)
params.PllMu       = 0.10;   % 环路增益 (实测 >=0.05 即达最优; 0.10 低 SNR 更好)

% ===== Pluto 硬件参数（L3 硬件闭环用）=====
params.CenterFrequency = 2.4e9;  % 载波中心频率 2.4 GHz (ISM)
params.TxGain          = -20;    % 发射增益 dB（低起步, RF安全）
params.RxGain          = 30;     % 接收增益 dB
params.RxFrames        = 8192;   % 接收端一次抓取采样数(应覆盖整帧+前导余量)

end
