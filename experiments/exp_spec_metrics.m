%% experiments/exp_spec_metrics.m
% 目的: 把方案说明书(spec_for_review.md)中"声称"的指标换成"实测"数据
%       直接回应外部评审提出的问题:
%         E1 帧检测自身的频偏容限   (评审#4 定时/检测论证)
%         E2 固定抽样的定时误差容限 (评审#4, 对应指标 P6)
%         E3 相位模糊 0/90/180/270  (评审#6, 验证已有相位校正)
%         E5 帧检测误检率 P_FA      (评审#7)
%         E6 去直流效果(真实数据)   (评审#11)
% 用法: matlab -batch "addpath('experiments'); exp_spec_metrics"

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, preambleSym] = gen_frame_sequences(params);
Nsym = params.PreambleSym + params.HeaderSym + params.PayloadSym;
Eg = sum(rrc.^2);

% 参考帧
msg = 'METRIC-TEST';
frameSym = tx_frame(int8(msg(:)), params, 0, 1);
symIdxTx = pskdemod(frameSym, M);
bitsTx = reshape(de2bi(symIdxTx, bp, 'left-msb').', [], 1);

% 前导成形波形(供帧检测用)
preUp = zeros(params.PreambleSym*L, 1); preUp(1:L:end) = preambleSym;
preambleWave = conv(preUp, rrc);
Np = length(preambleWave);
Ep = sum(abs(preambleWave).^2);

fprintf('\n############ 方案指标实测 (spec_for_review.md) ############\n');

%% ===== E1: 帧检测 rho vs 载波频偏 =====
% 前导时长 Tp = 32/250k = 128 us; 频偏会使相关峰幅度按 sinc(df*Tp) 衰减
fprintf('\n=== E1  帧检测 rho vs 载波频偏 (Eb/N0=20 dB) ===\n');
fprintf('理论: rho 按 sinc(df*Tp) 衰减, Tp=%d us\n', params.PreambleSym/params.SymbolRate*1e6);
fprintf('%10s | %12s | %12s | %8s\n', '频偏(Hz)', 'rho(真起点)', 'rho(最大值)', '能否检出');
fList = [0 200 500 1000 2000 3000 3500 4000 4500 5000 6000];
EbN0 = 10^(20/10); sig = sqrt(1*Eg/(2*EbN0*bp));
for f = fList
    rT = 0; rM = 0; det = 0; NT = 20;
    for tr = 1:NT
        rng(2000+tr);
        [w, ~] = tx_baseband(frameSym, L, rrc); w = w*0.9/max(abs(w));
        t = (0:length(w)-1).'/params.SampleRate;
        rx = w.*exp(1j*2*pi*f*t) + sig*(randn(size(w))+1j*randn(size(w)));
        cf = conv(rx, conj(flipud(preambleWave)));
        cm = abs(cf(Np:length(rx))); Nc = length(cm);
        p2 = abs(rx).^2; cp2 = [0; cumsum(p2)];
        Er = cp2(Np+1:Np+Nc) - cp2(1:Nc);
        rho = cm ./ sqrt(Er*Ep);
        rT = rT + rho(1); rM = rM + max(rho); det = det + (max(rho) > 0.60);
    end
    if det/NT > 0.5, ok = '是'; else, ok = '否'; end
    fprintf('%10d | %12.3f | %12.3f | %8s\n', f, rT/NT, rM/NT, ok);
end

%% ===== E2: BER vs 采样相位偏移 (固定抽样的定时误差容限) =====
fprintf('\n=== E2  BER vs 采样相位偏移 (Eb/N0=8 dB, 无频偏) ===\n');
fprintf('%14s | %10s | %12s\n', '偏移(采样)', '偏移(T)', 'BER');
dList = [0 0.125 0.25 0.375 0.5 0.75 1.0];
EbN0 = 10^(8/10); sig = sqrt(1*Eg/(2*EbN0*bp));
for d = dList
    acc = 0; NT = 60;
    for tr = 1:NT
        rng(3000+tr);
        [w, ~] = tx_baseband(frameSym, L, rrc); w = w*0.9/max(abs(w));
        rx = w + sig*(randn(size(w))+1j*randn(size(w)));
        sIdx = rxSymOffset(rx, d, params, rrc, preambleSym);
        bRx = reshape(de2bi(sIdx, bp, 'left-msb').', [], 1);
        acc = acc + mean(bitsTx ~= bRx);
    end
    if d == 0, tag = '0'; else, tag = sprintf('T/%.1f', L/d); end
    fprintf('%14.3f | %10s | %12.3e\n', d, tag, acc/NT);
end

%% ===== E3: 相位模糊 0/90/180/270 =====
fprintf('\n=== E3  注入固定相位 (Eb/N0=10 dB, 含公共相位校正) ===\n');
fprintf('%12s | %12s | %8s\n', '注入相位', 'BER', '全对?');
EbN0 = 10^(10/10); sig = sqrt(1*Eg/(2*EbN0*bp));
for ph = [0 90 180 270]
    acc = 0; NT = 40;
    for tr = 1:NT
        rng(4000+tr);
        [w, ~] = tx_baseband(frameSym, L, rrc); w = w*0.9/max(abs(w));
        rx = w*exp(1j*deg2rad(ph)) + sig*(randn(size(w))+1j*randn(size(w)));
        sIdx = rxSymOffset(rx, 0, params, rrc, preambleSym);
        bRx = reshape(de2bi(sIdx, bp, 'left-msb').', [], 1);
        acc = acc + mean(bitsTx ~= bRx);
    end
    if acc/NT < 1e-3, ok = '是'; else, ok = '否'; end
    fprintf('%10d 度 | %12.3e | %8s\n', ph, acc/NT, ok);
end

%% ===== E5: 帧检测误检率 P_FA (纯噪声) =====
% 注: rho 与信号幅度无关, 故噪声幅度任意
fprintf('\n=== E5  帧检测误检率 P_FA (纯噪声, %d 采样) ===\n', 4096);
Ntrial = 2000;
for th = [0.50 0.60 0.70 0.80]
    fa = 0;
    for tr = 1:Ntrial
        rng(5000+tr);
        rx = randn(4096,1) + 1j*randn(4096,1);
        fs_ = frame_detect(rx, preambleWave, L, th);
        fa = fa + ~isnan(fs_);
    end
    fprintf('  门限 %.2f : 误检 %4d / %d  =>  P_FA = %.3e\n', th, fa, Ntrial, fa/Ntrial);
end

%% ===== E6: 去直流效果 (真实空口数据) =====
fprintf('\n=== E6  去直流效果 (真实空口数据) ===\n');
if isfile('results/w3_rxData.mat')
    S = load('results/w3_rxData.mat'); rxData = S.rxData(:);
    dc = mean(rxData); rms = sqrt(mean(abs(rxData).^2));
    fprintf('DC = %.4e + j%.4e ; |DC|/RMS = %.2f %%\n', real(dc), imag(dc), abs(dc)/rms*100);
    for mode = [0 1]
        tag = '去DC前'; x = rxData;
        if mode == 1, tag = '去DC后'; x = rxData - dc; end
        try
            [pb, ~, dg] = rx_frame(x, params, scrambler, rrc);
            fprintf('%s: rhoMax=%.4f  freqEst=%7.1f Hz  解出="%s"\n', ...
                    tag, max(dg.corrMetric), dg.freqEst, char(pb(:)).');
        catch e
            fprintf('%s: 失败 (%s)\n', tag, e.message);
        end
    end
else
    fprintf('(未找到 results/w3_rxData.mat, 跳过)\n');
end

fprintf('\n############ 实测结束 ############\n');

%% ================= 局部函数 =================
function symIdx = rxSymOffset(rxWave, delta, params, rrc, preambleSym)
%RXSYMOFFSET  按指定采样相位偏移(delta 采样) 完成 匹配滤波→抽样→频偏补偿→相位校正→判决
%   delta: 等效于把抽样时刻从脉冲峰移开 delta 个采样 (delta=0.5 即半采样)
L = params.SamplesPerSym;
Nsym = params.PreambleSym + params.HeaderSym + params.PayloadSym;

% 匹配滤波
mfOut = conv(rxWave, rrc);

% 用 FFT 做小数延时 => 等价于改变抽样相位 (信号带宽远小于 fs/2, 精度足够)
N = length(mfOut);
F = fft(mfOut);
fr = (0:N-1).'/N; fr(fr>0.5) = fr(fr>0.5) - 1;
mfD = ifft(F .* exp(-1j*2*pi*fr*delta));

% 抽样
peak = length(rrc);
idx = peak : L : peak + (Nsym-1)*L;
rxSym = mfD(idx);

% 频偏估计 + 补偿
[~, rxComp] = freq_sync(rxSym, preambleSym, L, params.SymbolRate);

% 公共相位校正
ph = angle(mean(rxComp(1:params.PreambleSym) .* conj(preambleSym(:))));
rxComp = rxComp * exp(-1j*ph);

% 判决
ref = pskmod((0:params.M-1).', params.M);
[~, mi] = min(abs(rxComp.' - ref).^2, [], 1);
symIdx = (mi - 1).';
end
