function [symIdx, thetaHist, rxTracked] = phase_track(rxSym, preambleSym, M, mu)
%PHASE_TRACK  判决导向一阶锁相环 (DD-PLL) 相位跟踪
%
%   解决的问题 (本项目实测): 载波频偏估计器的残余误差会在【一个帧内】
%   累积成线性相位斜坡 —— 实测真频偏 0 时估计标准差 84 Hz @12 dB,
%   折合帧内漂移 35.9 度 (QPSK 判决边界 45 度), 导致帧尾判决大量出错。
%   表现为: 帧首 BER = 0.0000 单调恶化到帧尾 0.3857。
%
%   原理:
%     用【已知前导】估计初始相位 (消解 QPSK 4 重相位模糊 -> 防跳周),
%     然后逐符号用【局部判决】构造相位误差并驱动一阶环路:
%         y = r(k) * exp(-j*theta)          % 相位去旋转
%         s = decision(y)                   % 最近星座点判决
%         e = Im{ y * conj(s) }             % 相位误差检测 (≈ sin(相位误差))
%         theta <- theta + mu * e           % 一阶环路更新
%     关键在于使用【局部】判决逐步跟踪, 因此不要求全局判决正确 ——
%     这正是它优于"批量判决导向频偏精估"的原因 (后者在帧尾判决出错时崩溃,
%     见 notes/exp_w7_solution_study.md §4)。
%
%   输入:
%     rxSym       : 已做频偏补偿的符号序列 (Nsym x 1)。前 p 个为已知前导。
%     preambleSym : 已知前导符号 (p x 1, 单位幅度 QPSK 点)
%     M           : 调制阶数 (QPSK 为 4)
%     mu          : 环路增益, 默认 0.10 (实测: >=0.05 即达最优; 0.10 在低 SNR 更好)
%   输出:
%     symIdx    : 判决符号索引 (0..M-1), Nsym x 1
%     thetaHist : 跟踪到的相位轨迹 (Nsym x 1), 供诊断与报告绘图
%     rxTracked : 去旋转后的符号 (Nsym x 1), 供星座图使用
%
%   实测效果 (experiments/exp_phase_pll.m, 满载荷 62 字节):
%     Eb/N0    现状(前导常数校正)   本函数(mu=0.10)
%      8 dB        25%                90%
%     10 dB        35%                100%
%     12 dB        35%                100%
%     14 dB        65%                100%
%   注: 8 dB 时本函数(90%) 反超"已知真实频偏"方案(85%) ——
%       因为 PLL 把相位参考从 32 符号前导扩展到整帧 296 符号,
%       低 SNR 下相干积累更长, 相位估计本身也更准。
%
%   性能优化 (2026-09-12):
%     相位剖析显示本函数占单帧耗时的 38% (0.370 ms/帧)。为此对 QPSK 分支改用
%     【象限判决 + 误差查表】替代原来的"4 次星座点距离计算":
%       QPSK 星座点位于 0/90/180/270 度, 最近点判决等价于
%       "|实部| vs |虚部| + 符号"的象限判断 (4 次比较, 无需开方/求距离)。
%       相位误差 e = Im{y*conj(s)} 在四个方向分别等于 ±Im{y} 或 ±Re{y},
%       可直接查表, 省去复数乘法。数学上与原实现完全等价。
%     实测: 0.370 ms -> 0.025 ms (快 14.8 倍)
%
%   ⚠️ 重要修正 (同日, 自测发现):
%     初版把"方向->符号索引"的映射**硬编码**为 [1, j, -1, -j] (0/90/180/270 度),
%     但 MATLAB 的 pskmod(0:3,4) 实际为**格雷序**:
%         index 0 -> 1 (0度)   index 1 -> j (90度)
%         index 2 -> -j (270度) index 3 -> -1 (180度)
%     硬编码导致判决索引全错 (实测 0/20 帧正确, 帧号乱序)。
%     修正: **从 ref 数组在运行时推导**方向->索引映射 (见下), 不硬编码。
%     教训: 这类"为了提速而硬编码"的优化必须用回归测试兜底。
%
%   参考: notes/exp_w7_solution_study.md §5, notes/stage_w7_sync_tracking.md

if nargin < 4 || isempty(mu)
    mu = 0.10;
end

rxSym = rxSym(:);
p     = numel(preambleSym);
Nsym  = numel(rxSym);

if Nsym < p
    error('phase_track:short', '符号数(%d) 少于前导长度(%d)', Nsym, p);
end

% --- 初始相位: 由已知前导估计 (消解 4 重相位模糊, 防跳周) ---
theta = angle(mean(rxSym(1:p) .* conj(preambleSym(:))));

symIdx    = zeros(Nsym, 1);
thetaHist = zeros(Nsym, 1);
rxTracked = complex(zeros(Nsym, 1));

% 判断星座是否轴对齐 (QPSK 默认 pskmod 即为轴对齐: 点落在 0/90/180/270 度)
ref = pskmod((0:M-1).', M);
axisAligned = all( abs(abs(real(ref)) - 1) < 1e-9 & abs(imag(ref)) < 1e-9 | ...
                   abs(abs(imag(ref)) - 1) < 1e-9 & abs(real(ref)) < 1e-9 );

if M == 4 && axisAligned
    % ---------- QPSK 快路径: 方向判决 + 误差查表 ----------
    % 方向 1/2/3/4 分别对应 0/90/180/270 度。
    % ★ 索引映射从 ref **运行时推导**, 不硬编码 (pskmod 为格雷序!)
    dir2idx = zeros(1,4);
    for i = 1:M
        q = mod(round(angle(ref(i))/(pi/2)), 4) + 1;
        dir2idx(q) = i - 1;
    end

    for k = 1:Nsym
        y  = rxSym(k) * exp(-1j*theta);
        r  = real(y);
        im = imag(y);
        ar = abs(r);
        ai = abs(im);

        if ar > ai                    % 更靠近实轴 -> 方向 1 或 3
            if r >= 0
                q = 1;  e = im;       % 0 度  : e = Im{y}
            else
                q = 3;  e = -im;      % 180度 : e = -Im{y}
            end
        else                          % 更靠近虚轴 -> 方向 2 或 4
            if im >= 0
                q = 2;  e = -r;       % 90 度 : e = -Re{y}
            else
                q = 4;  e = r;        % 270度 : e =  Re{y}
            end
        end

        symIdx(k)    = dir2idx(q);
        rxTracked(k) = y;
        thetaHist(k) = theta;
        theta = theta + mu * e;       % 一阶环路更新
    end
else
    % ---------- 通用回退: 最近星座点距离判决 ----------
    for k = 1:Nsym
        y = rxSym(k) * exp(-1j*theta);
        [~, mi] = min(abs(y - ref).^2);
        sHat    = ref(mi);
        symIdx(k)    = mi - 1;
        rxTracked(k) = y;
        thetaHist(k) = theta;
        e     = imag(y * conj(sHat));
        theta = theta + mu * e;
    end
end

end
