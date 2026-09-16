%% ===== W3: Pluto 单板空口帧收发闭环 (含诊断) =====
% 目的: 把 W2 的全链路搬到 Pluto 上, 真实空口传递 "HELLO QPSK!"
% 用法: 在 MATLAB GUI 运行 (需 Support Package 注册)
% 准备: TX 口和 RX 口都装好短天线, 间隔 10cm+

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;

%% ---- 1. 发射: 组帧 + 成形 ----
msg = 'HELLO QPSK!';
dataB = int8(msg(:));
frameSym = tx_frame(dataB, params, 0, 0);
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[txWave, ~] = tx_baseband(frameSym, L, rrc);
% 关键: 不用 /max 归一化(max≈1), 改用 *0.9 充分利用 DAC 量程
% Pluto DAC 满刻度±1, 用 0.9 避免削波, 且信号功率更高
txWave = txWave * 0.9 / max(abs(txWave));
fprintf('[OK] 发送帧: %d 符号, 波形 %d 采样, 峰值幅度=%.3f\n', ...
        length(frameSym), length(txWave), max(abs(txWave)));

%% ---- 2. Pluto 发射 ----
tx = sdrtx('Pluto');
tx.CenterFrequency     = params.CenterFrequency;
tx.BasebandSampleRate  = params.SampleRate;
tx.Gain                = params.TxGain;
tx.OutputDataType      = 'double';
transmitRepeat(tx, txWave);
fprintf('[OK] 正在 %.3f GHz 发射, TxGain=%d dB\n', ...
        params.CenterFrequency/1e9, params.TxGain);

%% ---- 3. Pluto 接收 ----
rx = sdrrx('Pluto');
rx.CenterFrequency     = params.CenterFrequency;
rx.BasebandSampleRate  = params.SampleRate;
rx.GainSource          = 'Manual';
rx.Gain                = params.RxGain;        % 必要时手动调到 40+
rx.SamplesPerFrame     = params.RxFrames;
rx.OutputDataType      = 'double';

% 抓取多帧拼接
nTries = 5;
rxData = [];
for i = 1:nTries
    d = rx();
    rxData = [rxData; d];
end
fprintf('[OK] 抓取 %d 帧, 共 %d 采样\n', nTries, length(rxData));

%% ---- 3.5 诊断: 信号强度 vs 噪声 ----
sigPower = mean(abs(rxData).^2);
fprintf('[DIAG] 接收数据平均功率 = %.3e (|rx| RMS = %.4f)\n', sigPower, sqrt(sigPower));

% 保存 rxData 供后续分析
if ~isfolder('results'); mkdir('results'); end
save('results/w3_rxData.mat','rxData','txWave','rrc','params','-v7');
fprintf('[DIAG] 已保存 rxData 到 results/w3_rxData.mat\n');

%% ---- 4. 接收处理 ----
[~, scrambler, ~] = gen_frame_sequences(params);
[payloadBytes, headerInfo, diag] = rx_frame(rxData, params, scrambler, rrc);

%% ---- 5. 诊断: 相关峰列表 ----
m = abs(diag.corrMetric);
[topVals, topIdx] = sort(m, 'descend');
fprintf('\n[DIAG] 帧检测 Top-5 相关峰:\n');
for k = 1:min(5, length(topVals))
    fprintf('  #%d: 位置=%6d, 相关值=%.4f\n', k, topIdx(k), topVals(k));
end
fprintf('  真实帧起点(理论)= 1 (循环发射, 应每 1208 采样一个峰)\n');

%% ---- 6. 结果 ----
recvMsg = char(payloadBytes(:)).';
fprintf('\n===== 空口结果 =====\n');
fprintf('帧起点: %d, 频偏估计: %.1f Hz\n', diag.frameStart, diag.freqEst);
fprintf('帧头: type=%d nBytes=%d frameNum=%d crcOK=%d\n', ...
    headerInfo.frameType, headerInfo.nBytes, headerInfo.frameNum, headerInfo.crcOK);
fprintf('解出: "%s"\n', recvMsg);
if strcmp(recvMsg, msg)
    fprintf('[PASS] 真实空口成功!\n');
else
    fprintf('[FAIL] 请看诊断输出判断: 信号太弱/天线距离/帧检测问题\n');
end

%% ---- 7. 停止发射并释放 ----
release(tx);
release(rx);
fprintf('[OK] 已停止发射\n');

%% ---- 8. 星座图 ----
figure('Name','W3 空口星座','Color','w');
pIdx = params.PreambleSym + params.HeaderSym + 1;
plot(real(diag.rxSymComp(pIdx:end)), imag(diag.rxSymComp(pIdx:end)),'b.','MarkerSize',4);
axis equal; xlim([-1.5 1.5]); ylim([-1.5 1.5]); grid on;
xlabel('I'); ylabel('Q'); title('空口 QPSK 星座 (补偿后)');

if ~isfolder('plots'); mkdir('plots'); end
saveas(gcf, 'plots/w3_overair_constellation.png');
fprintf('[OK] 图已保存: plots/w3_overair_constellation.png\n');