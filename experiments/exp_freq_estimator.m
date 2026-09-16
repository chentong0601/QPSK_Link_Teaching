%% experiments/exp_freq_estimator.m
% 目的: 回答 spec Q10 —— 哪种方式能真正降低频偏估计误差?
%        (背景: 实测发现现有接收机误码主因 = 频偏估计残余的帧内相位斜坡,
%         frecEst 标准差 84 Hz @12dB -> 帧内漂移 35.9 度)
%
% 做法: 在【相同前导长度】【相同 SNR】下比较 4 类估计器设计, 并做前导长度扫描。
%        符号级仿真(排除成形/定时的干扰, 只看估计器本身)
%
% 用法: matlab -batch "addpath('experiments'); exp_freq_estimator"

clear; clc;
addpath('config');
params = init_params;
Rs = params.SymbolRate;  Ts = 1/Rs;
NsymFrame = params.PreambleSym + params.HeaderSym + params.PayloadSym;

SNRdB = 12;  gamma = 10^(SNRdB/10);      % 每符号 Es/N0
sig = sqrt(1/(2*gamma));                 % 单位幅度符号 + 复噪(每维 sig)
Ntr = 4000;                              % 试验次数

fprintf('\n############ 频偏估计器对比 (spec Q10) ############\n');
fprintf('符号级仿真: 每符号 Es/N0 = %d dB, 真频偏 = 0, %d 次试验\n', SNRdB, Ntr);
fprintf('前导长度 p 决定帧开销: p=32 -> 帧长 %d, 效率 %.1f%%\n\n', NsymFrame, 248/NsymFrame*100);

%% ===== 实验 A: 相同前导长度 (p=32) 下比较 4 种设计 =====
p = 32;  nRep = 4;  Nbase = p/nRep;      % 重复结构: 4 块 x 8 符号
fprintf('=== A. 相同前导长度 p=%d, 比较不同估计器设计 ===\n', p);
fprintf('%-34s | %12s | %12s\n', '估计器设计', 'sigma_f(Hz)', '帧内漂移(度)');
fprintf('%s\n', repmat('-', 1, 64));

res = struct();

% A1: 伪随机前导 + 首尾分段 (现状)
rng(42); preRand = pskmod(randi([0 3], p, 1), 4);
f = zeros(Ntr,1);
for t = 1:Ntr
    rng(1000+t);
    r = rxPreamble(preRand, 0, sig);
    f(t) = estTwoSeg(r .* conj(preRand), Rs);
end
res.A1 = f;

% A2: 伪随机前导 + ML (FFT 全序列, 用上所有符号)
f = zeros(Ntr,1);
for t = 1:Ntr
    rng(1000+t);
    r = rxPreamble(preRand, 0, sig);
    f(t) = estML(r .* conj(preRand), Rs);
end
res.A2 = f;

% A3: 重复前导(4x8) + 相邻块相关 + 多段平均  (参照 jens-sam 做法)
rng(7); base = pskmod(randi([0 3], Nbase, 1), 4);
preRep = repmat(base, nRep, 1);
f = zeros(Ntr,1);
for t = 1:Ntr
    rng(1000+t);
    r = rxPreamble(preRep, 0, sig);
    f(t) = estRepeatBlocks(r .* conj(preRep), Nbase, Rs);
end
res.A3 = f;

% A4: 重复前导(4x8) + ML
f = zeros(Ntr,1);
for t = 1:Ntr
    rng(1000+t);
    r = rxPreamble(preRep, 0, sig);
    f(t) = estML(r .* conj(preRep), Rs);
end
res.A4 = f;

% A5: 伪随机前导 + 相位线性回归
f = zeros(Ntr,1);
for t = 1:Ntr
    rng(1000+t);
    r = rxPreamble(preRand, 0, sig);
    f(t) = estRegress(r .* conj(preRand), Rs);
end
res.A5 = f;

names = {'A1 伪随机+首尾分段(现状)','A2 伪随机+ML(全序列)', ...
         'A3 重复4x8+相邻块平均','A4 重复4x8+ML','A5 伪随机+相位线性回归'};
keys = {'A1','A2','A3','A4','A5'};
for i = 1:numel(keys)
    v = res.(keys{i});
    drift = std(v)*360*NsymFrame/Rs;
    fprintf('%-34s | %12.1f | %12.1f\n', names{i}, std(v), drift);
end

%% ===== 实验 B: 首尾分段法的 Nseg 扫描 (验证 Nseg=8 是否最优) =====
fprintf('\n=== B. 首尾分段法: 分段长度 Nseg 扫描 (p=%d) ===\n', p);
fprintf('%8s | %12s | %12s\n', 'Nseg', 'sigma_f(Hz)', '帧内漂移(度)');
for Nseg = [2 4 6 8 10 12 14 16]
    f = zeros(Ntr,1);
    for t = 1:Ntr
        rng(1000+t);
        r = rxPreamble(preRand, 0, sig);
        f(t) = estTwoSeg(r .* conj(preRand), Rs, Nseg);
    end
    fprintf('%8d | %12.1f | %12.1f\n', Nseg, std(f), std(f)*360*NsymFrame/Rs);
end

%% ===== 实验 C: 前导长度扫描 (关键: 验证 sigma_f 随长度下降的规律) =====
fprintf('\n=== C. 前导长度扫描 (首尾分段 vs ML) ===\n');
fprintf('%6s | %8s | %14s | %14s | %12s\n', 'p', '帧效率', '两段sigma_f', 'ML sigma_f', '漂移(ML)');
fprintf('%s\n', repmat('-', 1, 68));
for p2 = [32 48 64 96 128]
    rng(42); pr = pskmod(randi([0 3], p2, 1), 4);
    f1 = zeros(Ntr,1); f2 = zeros(Ntr,1);
    for t = 1:Ntr
        rng(1000+t);
        r = rxPreamble(pr, 0, sig);
        d = r .* conj(pr);
        f1(t) = estTwoSeg(d, Rs);
        f2(t) = estML(d, Rs);
    end
    Nf2 = p2 + params.HeaderSym + params.PayloadSym;
    fprintf('%6d | %7.1f%% | %14.1f | %14.1f | %12.1f\n', ...
        p2, 248/Nf2*100, std(f1), std(f2), std(f2)*360*Nf2/Rs);
end

%% ===== 局部函数 =====
function r = rxPreamble(preSym, df, sig)
% 生成接收前导符号: 已知前导 + 频偏旋转 + 解调噪声
    n = (0:length(preSym)-1).';
    Rs = 250e3;
    r = preSym .* exp(1j*(2*pi*df*n/Rs)) + sig*(randn(size(preSym)) + 1j*randn(size(preSym)));
end

function fh = estTwoSeg(d, Rs, Nseg)
% 首尾分段相位差法 (本项目现状; Nseg 默认 p/4)
    p = length(d);
    if nargin < 3, Nseg = max(1, round(p/4)); end
    Nseg = min(Nseg, floor(p/2));
    z1 = mean(d(1:Nseg));
    z2 = mean(d(p-Nseg+1:p));
    gap = p - Nseg;
    fh = angle(z2 * conj(z1)) / (2*pi*(gap/Rs));
end

function fh = estRepeatBlocks(d, Nbase, Rs)
% 重复前导: 相邻块共轭相关 + 多段平均 (jens-sam 风格)
    nB = floor(length(d)/Nbase);
    J = 0;
    for i = 1:nB-1
        blk1 = d((i-1)*Nbase+1 : i*Nbase);
        blk2 = d(i*Nbase+1 : (i+1)*Nbase);
        J = J + sum(blk2 .* conj(blk1));
    end
    fh = angle(J) / (2*pi*(Nbase/Rs));
end

function fh = estML(d, Rs)
% 已知序列的 ML 频偏估计: 对去调制序列做 FFT 找峰 (+ 抛物线插值细化)
    Nfft = 2^16;
    F = fftshift(fft(d, Nfft));
    m = abs(F);
    [~, i] = max(m);
    ax = (-Nfft/2:Nfft/2-1).'/Nfft*Rs;
    % 抛物线插值
    if i > 1 && i < Nfft
        a = m(i-1); b = m(i); c = m(i+1);
        den = (a - 2*b + c);
        if abs(den) > eps
            delta = 0.5*(a - c)/den;
        else
            delta = 0;
        end
        fh = ax(i) + delta*(Rs/Nfft);
    else
        fh = ax(i);
    end
end

function fh = estRegress(d, Rs)
% 去调制序列的相位线性回归
    ph = unwrap(angle(d));
    n = (0:length(d)-1).';
    pp = polyfit(n, ph, 1);
    fh = pp(1)*Rs/(2*pi);
end
