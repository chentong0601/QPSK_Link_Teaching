function [freqEst, rxComp] = freq_sync(rxFrame, preambleSym, L, Rs, varargin)
%FREQ_SYNC  载波频偏估计与补偿 (前导首尾分段相关相位差法)
%   输入:
%     rxFrame    : 已对齐的接收帧 (符号级, 前 p 个是前导) 或采样域(varargin)
%     preambleSym: 已知前导符号 (复列向量, 长度 p, QPSK 星座点)
%     L          : 每符号采样数
%     Rs         : 符号率 Hz
%   输出:
%     freqEst    : 估计频偏 Hz
%     rxComp     : 补偿后的符号序列
%
%   算法 (去调制 + 首尾分段相关, 最大化相关间隔以抗噪):
%     1) 去调制:  d = rxPre .* conj(preambleSym)
%                => d(k) ≈ A·exp(j(2πΔf·k·Ts + θ0)) + noise (只剩频偏旋转)
%     2) 取前段 S1 = 前 Nseg 个符号, 后段 S2 = 末 Nseg 个符号
%        分别做相干平均(在 d 上):  z1 = mean(S1), z2 = mean(S2)
%        => 各自降噪 sqrt(Nseg) 倍
%     3) 相位差:  Δθ = angle(z2 · conj(z1))
%        对应时间间隔 T_sep = (p - Nseg) / Rs   (前段中心到后段中心)
%        => Δf̂ = Δθ / (2π·T_sep)
%   优点: 相关间隔 T_sep 最大化(≈整个前导长度) => 相位累积大 => 抗噪
%   估计范围: |Δθ|<π => |Δf̂| < Rs/(2·(p-Nseg))
%     p=32,Nseg=8 => 范围 < ±5208 Hz, 覆盖需求(几百Hz) 充裕

p = length(preambleSym);

% --- 输入处理 ---
if nargin >= 5 && strcmpi(varargin{1},'wave')
    rxSym = rxFrame(1:L:end);
    rxSym = rxSym(1:floor(length(rxFrame)/L));
else
    rxSym = rxFrame;
end

% --- 去调制 (前导段) ---
rxPre = rxSym(1:p);
d = rxPre .* conj(preambleSym(:));       % 只剩频偏旋转+噪声

% --- 首尾分段相干平均 (降噪) ---
Nseg = max(1, round(p/4));               % 每段取 1/4 前导长度
z1 = mean(d(1:Nseg));                    % 前段
z2 = mean(d(p-Nseg+1:p));                % 后段

% --- 相位差 → 频偏 ---
dTheta = angle(z2 * conj(z1));
% 两段中心间隔: 前段中心≈(Nseg+1)/2, 后段中心≈p-(Nseg-1)/2
centerGap = p - Nseg;                    % 近似符号间隔(足够精度)
T_sep = centerGap / Rs;
freqEst = dTheta / (2*pi*T_sep);

% --- 估计范围自检 ---
estRange = Rs / (2*centerGap);
if abs(freqEst) > 0.9*estRange
    warning('freq_sync:range', '频偏接近估计上限 ±%.0f Hz', estRange);
end

% --- 补偿 ---
nSym = length(rxSym);
tSym = (0:nSym-1).' / Rs;
rxComp = rxSym .* exp(-1j*2*pi*freqEst .* tSym);

end
