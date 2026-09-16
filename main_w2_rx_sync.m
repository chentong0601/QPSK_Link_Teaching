%% ===== W2: 接收端同步算法全链路仿真验证 =====
% 目标: 发射端组帧成形 → 加 AWGN + 注入频偏(模拟真实晶振失配)
%       → 接收端: 帧检测 + 频偏补偿 + 解调 → 正确还原 "HELLO QPSK!"
% 关键验证点:
%   1. 帧检测: 相关峰出现在正确位置
%   2. 频偏估计: 估出 ≈ 注入的频偏
%   3. 补偿后: 星座收敛(对比补偿前"转圈"), 文字解出
% 用法: matlab -batch "main_w2_rx_sync"

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;

M          = params.M;
bitsPerSym = params.bitsPerSym;
L          = params.SamplesPerSym;

%% ---- 1. 发射端: 组帧 + 成形 ----
msg    = 'HELLO QPSK!';
dataB  = int8(msg(:));
frameSym = tx_frame(dataB, params, 0, 0);          % 类型0=文字

rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[txWave, ~] = tx_baseband(frameSym, L, rrc);
txWave = txWave / max(abs(txWave));                 % 归一化
fprintf('[OK] 发送帧: %d 符号, 波形 %d 采样, payload="%s"\n', ...
        length(frameSym), length(txWave), msg);

%% ---- 2. 信道: AWGN + 注入频偏 ----
EbN0dB = 12;                                        % 较高信噪比(聚焦验证同步)
EbN0   = 10^(EbN0dB/10);
% 符号能量: 星座单位功率 => Es≈1; 波形噪声标定(与阶段2同法)
sigPower = mean(abs(txWave).^2);
Eg       = sum(rrc.^2);
SNRsym   = EbN0 * bitsPerSym;
sigma    = sqrt(sigPower * Eg / (2*SNRsym));        % 每维噪声标准差

% 注入频偏: 用两块晶振失配的典型值 (25ppm @ 2.4GHz ≈ 60kHz? 但基带可见的是相对值)
% 实际: Pluto基带频偏通常 < 几百 Hz (晶振误差在射频被混频到基带)
fInj = 300;                                         % 注入 300 Hz (模拟异源晶振)
t    = (0:length(txWave)-1).'/params.SampleRate;
rxWave = txWave .* exp(1j*2*pi*fInj.*t);            % 频偏
rxWave = rxWave + sigma*(randn(size(rxWave)) + 1j*randn(size(rxWave)));
fprintf('[OK] 注入频偏 %d Hz, Eb/N0=%.0f dB\n', fInj, EbN0dB);

%% ---- 3. 接收端: 帧检测 + 频偏补偿 + 解调 ----
% 用 gen_frame_sequences 拿扰码
[~, scrambler, ~] = gen_frame_sequences(params);
[payloadBytes, headerInfo, diag] = rx_frame(rxWave, params, scrambler, rrc);

%% ---- 4. 结果检查 ----
recvMsg = char(payloadBytes(:)).';
fprintf('\n===== 解调结果 =====\n');
fprintf('帧起点估计: %d (真实帧起点=1, 因为从txWave起点发射)\n', diag.frameStart);
fprintf('频偏估计:   %.1f Hz (注入 %.0f Hz, 误差 %.1f Hz)\n', ...
        diag.freqEst, fInj, abs(diag.freqEst-fInj));
fprintf('帧头: type=%d, nBytes=%d, frameNum=%d, crcOK=%d\n', ...
        headerInfo.frameType, headerInfo.nBytes, headerInfo.frameNum, headerInfo.crcOK);
fprintf('解出消息: "%s"\n', recvMsg);
if strcmp(recvMsg, msg)
    fprintf('[PASS] 消息完整还原!\n');
else
    fprintf('[FAIL] 消息不匹配\n');
end

%% ---- 5. 图: 频偏补偿效果 (关键报告插图) ----
% 补偿前符号(抽样): 从 rxSymFrame 直接取, 显示星座旋转
rxSymBefore = diag.rxSym;         % 补偿前
rxSymAfter  = diag.rxSymComp;     % 补偿后

% 只画 payload 中段(避开前导/帧头) 观察星座
pIdx = params.PreambleSym + params.HeaderSym + 1;

figure('Name','W2 频偏补偿效果','Position',[80 80 1000 480],'Color','w');

subplot(1,3,1);
plot(real(rxSymBefore(pIdx:end)), imag(rxSymBefore(pIdx:end)),'r.','MarkerSize',4);
axis equal; xlim([-2 2]); ylim([-2 2]); grid on;
title('补偿前: 星座在"转圈"');
xlabel('I'); ylabel('Q');

subplot(1,3,2);
plot(real(rxSymAfter(pIdx:end)), imag(rxSymAfter(pIdx:end)),'b.','MarkerSize',4);
axis equal; xlim([-1.5 1.5]); ylim([-1.5 1.5]); grid on;
title('补偿后: 星座收敛到 4 点');
xlabel('I'); ylabel('Q');

subplot(1,3,3);
% 帧检测相关峰
m = abs(diag.corrMetric);
plot(1:length(m), m/max(m),'b'); hold on;
xline(diag.frameStart, '--r');
xlabel('采样序号'); ylabel('归一化相关'); grid on;
title(sprintf('帧检测: 相关峰 @%d', diag.frameStart));
xlim([1 min(length(m),4000)]);

if ~isfolder('plots'); mkdir('plots'); end
saveas(gcf, 'plots/w2_freq_compensation.png');
fprintf('[OK] 图已保存: plots/w2_freq_compensation.png\n');
