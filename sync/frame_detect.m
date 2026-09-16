function [frameStart, corrMetric] = frame_detect(rxWave, preambleWave, L, threshRatio)
%FRAME_DETECT  帧检测: 用前导波形做归一化滑动相关, 返回**帧起点采样索引**
%   输入:
%     rxWave       : 接收波形 (复列向量, 采样率 fs = L*Rs)
%     preambleWave : 前导的成形波形 (tx_frame 前导符号过 RRC 后的波形)
%                   长度 Np = PreambleSym*L + len(rrc) - 1
%     L            : 每符号采样数
%     threshRatio  : (可选) 归一化相关峰门限 (默认 0.35, 见下)
%   输出:
%     frameStart   : 检测到的帧起点(第1个前导符号)的采样索引
%                    若未检测到返回 NaN
%     corrMetric   : 归一化相关度量 (长度 = length(rxWave)-Np+1)
%
%   原理 (见 notes/design.md §4.2):
%     原始相关   C[n] = Σ_m r[n+m]·p*[m]      (匹配滤波)
%     ↑ 问题: C[n] 幅度随接收信号功率变化, 固定门限在连续接收时失效。
%     归一化相关 ρ[n] = |C[n]| / sqrt(E_r[n]·E_p)
%       E_r[n] = Σ_m |r[n+m]|^2  (窗内接收能量, 滑动)
%       E_p    = Σ_m |p[m]|^2    (前导能量, 常数)
%     ρ[n] ∈ [0,1] 是**与信号幅度无关**的相关系数 → 门限可固定, 适合连续接收。
%     无帧: ρ ≈ 噪声互相关 / 能量 ≈ 小; 帧到: ρ → 1 的尖锐峰。
%
%   对齐关系:
%     用 conv(rxWave, conj(flipud(p))) 时, 相关峰出现在 (帧起点 + Np - 1)。
%     故 帧起点 = 峰值索引 - (Np - 1)。本函数直接返回帧起点, 调用者无需换算。

preambleWave = preambleWave(:);
rxWave       = double(rxWave(:));
Np = length(preambleWave);
if length(rxWave) < Np
    frameStart = NaN; corrMetric = [];
    return;
end

%% ---- 1. 滑动相关 (匹配滤波) ----
corrFull   = conv(rxWave, conj(flipud(preambleWave)));
% conv 全长 = N + Np - 1; 与 rxWave 对齐的有效相关段为 corrFull(Np : N)
% 长度 = N - Np + 1, 对应该窗起点 n = 1 .. N-Np+1
corrMetric = abs(corrFull(Np : length(rxWave)));
Nc = length(corrMetric);

%% ---- 2. 滑动窗能量 (用于归一化) ----
% 窗内接收能量 E_r[n] = Σ_{m=0..Np-1} |rxWave[n+m]|^2, n = 1..Nc
p2      = abs(rxWave).^2;
cumP2   = [0; cumsum(p2)];
Er      = cumP2(Np+1 : Np+Nc) - cumP2(1 : Nc);   % 长度 Nc

Ep      = sum(abs(preambleWave).^2);
denom   = sqrt(Er * Ep);
denom(denom < eps) = eps;                       % 防除零
rho     = corrMetric ./ denom;                  % 归一化相关 ∈[0,1]

corrMetric = rho;                               % 对外返回归一化度量

%% ---- 3. 门限检测 (归一化门限, 与幅度无关) ----
if nargin < 4
    threshRatio = 0.60;
    % 经验值标定 (实测): 真峰 ρ≈0.90, 噪声/旁瓣 ρ≈0.35~0.44
    % 取 0.60 在两者之间留足双向余量, 虚警率极低。
    % (早期用 0.35 会把噪声旁瓣当帧 => 缓冲被错误消费 => 后续帧全崩)
end
thresh = threshRatio;

above = find(rho > thresh);
if isempty(above)
    frameStart = NaN;
    return;
end

% 第一个超门限点, 再在附近找局部最大 (避免取到上升沿)
i0 = above(1);
iEnd = min(i0 + round(2*L), length(rho));
[~, rel] = max(rho(i0:iEnd));
peakIdx = i0 + rel - 1;            % 相关峰在 corrMetric 中的索引

% ---- 关键: corrMetric 的索引 == 帧起点 ----
% 推导: conv(rxWave, conj(flipud(p))) 的峰出现在 k = frameStart + Np - 1;
%       切掉前 Np-1 个后, 索引 idx = k-(Np-1) = frameStart。
%       故 corrMetric(idx) 的 idx 本身就是帧起点采样位置。
frameStart = peakIdx;

if frameStart < 1
    % 峰太靠前(帧起点被削), 退化为从 1 开始 (由调用者判长度)
    frameStart = 1;
end

end
