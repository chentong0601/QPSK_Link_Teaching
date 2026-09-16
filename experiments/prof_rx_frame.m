%% experiments/prof_rx_frame.m
% P5 发现的实时性瓶颈 —— 定位 rx_frame 内部各阶段耗时
% 背景: P5 实测接收侧耗时 = 信号时长的 135% (1.74 ms/帧 > 帧周期 0.296 ms)
%       本脚本用数据定位瓶颈, 再决定优化方向 (避免凭猜测优化)
% 用法: matlab -batch "addpath('experiments'); prof_rx_frame"

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;
Rs = params.SymbolRate;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, preSym] = gen_frame_sequences(params);
Nsym = params.PreambleSym + params.HeaderSym + params.PayloadSym;
peak = length(rrc);

% 构造真实场景的缓冲长度 (rx_receiver 中约 2 帧长)
frameBodyLen = Nsym*L;
BUF_LEN = frameBodyLen + 1200;      % ≈2400 采样

msg = [sprintf('PKT-%03d-',0) repmat('X',1,54)];
fSym = tx_frame(int8(msg(:)), params, 0, 0);
[w,~] = tx_baseband(fSym, L, rrc); w = w*0.9/max(abs(w));
Es = L*mean(abs(w).^2);
sg = sqrt(Es/(2*10^(12/10)*bp));

rng(1);
buf = [w; zeros(BUF_LEN-numel(w),1)];      % 帧 + 余量(模拟缓冲)
buf = buf .* exp(1j*2*pi*320*(0:numel(buf)-1).'/params.SampleRate);
buf = buf + sg*(randn(size(buf))+1j*randn(size(buf)));

fprintf('\n===== rx_frame 阶段耗时剖析 (缓冲 %d 采样) =====\n\n', numel(buf));
N = 200;

% --- 0. 总耗时 (调用生产函数) ---
for i=1:5, rx_frame(buf, params, scrambler, rrc); end
t0=tic; for i=1:N, [~,~,dg] = rx_frame(buf, params, scrambler, rrc); end
tTotal = toc(t0)/N*1000;

% --- 1. 前导波形构造 (每次调用都重算!) ---
t0=tic;
for i=1:N
    [~,~,pSym] = gen_frame_sequences(params);
    preUp = zeros(params.PreambleSym*L,1); preUp(1:L:end) = pSym;
    pw = conv(preUp, rrc);
end
tPwBuild = toc(t0)/N*1000;

% --- 2. gen_frame_sequences 单独 (含 rng 重置!) ---
t0=tic; for i=1:N, gen_frame_sequences(params); end
tGenSeq = toc(t0)/N*1000;

% --- 3. 帧检测 (主要嫌疑) ---
% 先显式构造一次前导波形, 供后续各段共用
[~, ~, pSym] = gen_frame_sequences(params);
preUp = zeros(params.PreambleSym*L,1); preUp(1:L:end) = pSym;
pw = conv(preUp, rrc);
Np = numel(pw);
t0=tic;
for i=1:N
    corrFull = conv(buf, conj(flipud(pw)));
    cm = abs(corrFull(Np:numel(buf)));
    p2 = abs(buf).^2; cp2 = [0; cumsum(p2)];
    Nc = numel(cm);
    Er = cp2(Np+1:Np+Nc) - cp2(1:Nc);
    rho = cm ./ sqrt(Er*sum(abs(pw).^2));
    [~, i0] = max(rho);
end
tDetect = toc(t0)/N*1000;

% --- 4. 匹配滤波 + 抽样 ---
fs0 = frame_detect(buf, pw, L);
rxF = buf(fs0 : fs0 + (Nsym+1)*L + length(rrc) - 1);
t0=tic; for i=1:N, mfOut = conv(rxF, rrc); end
tMatch = toc(t0)/N*1000;

% --- 5. 频偏估计 ---
rs = mfOut(peak : L : peak+(Nsym-1)*L);
t0=tic; for i=1:N, freq_sync(rs, pSym, L, Rs); end
tFreq = toc(t0)/N*1000;

% --- 6. DD-PLL ---
[~, rc] = freq_sync(rs, pSym, L, Rs);
ph = angle(mean(rc(1:params.PreambleSym).*conj(pSym(:))));
rc = rc*exp(-1j*ph);
t0=tic; for i=1:N, phase_track(rc, pSym, M, 0.10); end
tPll = toc(t0)/N*1000;

fprintf('%28s | %10s | %8s\n','阶段','耗时(ms)','占比');
fprintf('%s\n', repmat('-',1,52));
fprintf('%28s | %10.3f | %7.1f%%\n','【总】rx_frame (生产函数)', tTotal, 100);
fprintf('%28s | %10.3f | %7.1f%%\n','  前导波形构造 (每帧重算)', tPwBuild, tPwBuild/tTotal*100);
fprintf('%28s | %10.3f | %7.1f%%\n','    其中 gen_frame_sequences', tGenSeq, tGenSeq/tTotal*100);
fprintf('%28s | %10.3f | %7.1f%%\n','  帧检测 (滑动相关+归一化)', tDetect, tDetect/tTotal*100);
fprintf('%28s | %10.3f | %7.1f%%\n','  匹配滤波 conv(rxF,rrc)', tMatch, tMatch/tTotal*100);
fprintf('%28s | %10.3f | %7.1f%%\n','  频偏估计 freq_sync', tFreq, tFreq/tTotal*100);
fprintf('%28s | %10.3f | %7.1f%%\n','  DD-PLL phase_track', tPll, tPll/tTotal*100);
s = tPwBuild + tDetect + tMatch + tFreq + tPll;
fprintf('%s\n', repmat('-',1,52));
fprintf('%28s | %10.3f | %7.1f%%\n','五阶段合计', s, s/tTotal*100);
fprintf('%28s | %10.3f | %7.1f%%\n','其他(判决/解扰/帧头/开销)', tTotal-s, (tTotal-s)/tTotal*100);

fprintf('\n帧周期 = %.3f ms ; 当前 %.3f ms => 需加速 %.1f 倍才能实时\n', ...
        Nsym/Rs*1000, tTotal, tTotal/(Nsym/Rs*1000));

fprintf('\n===== 优化方向优先级 (按占比) =====\n');
[~, ord] = sort([tPwBuild tDetect tMatch tFreq tPll], 'descend');
nm = {'前导波形构造(可缓存!)','帧检测','匹配滤波','频偏估计','DD-PLL'};
vv = [tPwBuild tDetect tMatch tFreq tPll];
for i=1:5
    fprintf('  %d. %-24s %.3f ms (%.1f%%)\n', i, nm{ord(i)}, vv(ord(i)), vv(ord(i))/tTotal*100);
end
fprintf('\n');
