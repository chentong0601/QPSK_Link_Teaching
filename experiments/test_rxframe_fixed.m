%% 用真实数据测试修复后的 rx_frame
clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
load('results/w3_rxData.mat');   % rxData, rrc, params
params = init_params;
[~, scrambler, ~] = gen_frame_sequences(params);

% 用修复后的 rx_frame 处理真实数据
[payloadBytes, headerInfo, diag] = rx_frame(rxData, params, scrambler, rrc);

recvMsg = char(payloadBytes(:)).';
fprintf('===== 修复后 rx_frame 结果 (真实空口数据) =====\n');
fprintf('帧起点: %d\n', diag.frameStart);
fprintf('频偏估计: %.1f Hz\n', diag.freqEst);
fprintf('公共相位: %.1f 度\n', rad2deg(diag.phaseOffset));
fprintf('帧头: type=%d nBytes=%d frameNum=%d crcOK=%d\n', ...
    headerInfo.frameType, headerInfo.nBytes, headerInfo.frameNum, headerInfo.crcOK);
fprintf('解出: "%s"\n', recvMsg);
if strcmp(recvMsg, 'HELLO QPSK!')
    fprintf('[PASS] 修复成功! 真实空口数据完整还原!\n');
else
    fprintf('[FAIL]\n');
end
