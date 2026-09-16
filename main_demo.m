%% ===== 项目演示脚本 (一键演示) =====
% 用途: 课堂/答辩现场演示完整 QPSK 空口链路
% 用法: MATLAB GUI 运行 (需硬件)
% 流程: 发射文字 -> 空口 -> 接收解调 -> 显示星座图 + 还原消息
%
% 演示要点:
%   1. 实时星座图 (看到 QPSK 信号"活"着)
%   2. 帧检测相关峰 (看到帧同步过程)
%   3. 文字还原 (看到信息真的传过来了)

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M=params.M; bp=params.bitsPerSym; L=params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

fprintf('========================================\n');
fprintf('  QPSK 空口链路演示\n');
fprintf('========================================\n');

%% ---- 演示内容 (可修改) ----
msg = 'HELLO QPSK! DEMO';
fprintf('\n[1/5] 待发送消息: "%s"\n', msg);

%% ---- 组帧 ----
frameSym = tx_frame(int8(msg(:)), params, 0, 0);
[txWave, ~] = tx_baseband(frameSym, L, rrc);
txWave = txWave * 0.9/max(abs(txWave));
fprintf('[2/5] 组帧完成: %d 符号 (%d 前导 + %d 帧头 + %d 数据)\n', ...
    length(frameSym), params.PreambleSym, params.HeaderSym, params.PayloadSym);

%% ---- 发射 ----
tx = sdrtx('Pluto');
tx.CenterFrequency = params.CenterFrequency;
tx.BasebandSampleRate = params.SampleRate;
tx.Gain = params.TxGain;
tx.OutputDataType = 'double';
transmitRepeat(tx, txWave);
fprintf('[3/5] 正在 %.2f GHz 发射 (TxGain=%d dB)...\n', ...
    params.CenterFrequency/1e9, params.TxGain);

%% ---- 接收 ----
rx = sdrrx('Pluto');
rx.CenterFrequency = params.CenterFrequency;
rx.BasebandSampleRate = params.SampleRate;
rx.GainSource = 'Manual';
rx.Gain = 40;
rx.SamplesPerFrame = params.RxFrames;
rx.OutputDataType = 'double';

% 多次尝试直到成功 (演示容错)
nTry = 10; ok = false; recvMsg = ''; dg = [];
for k = 1:nTry
    d = rx();
    try
        [pb, hdr, dg] = rx_frame(d, params, scrambler, rrc);
        recvMsg = char(pb(:)).';
        if strcmp(recvMsg, msg), ok = true; break; end
    catch
    end
end
fprintf('[4/5] 接收解调: 尝试 %d 次, 频偏估计 %.1f Hz\n', k, dg.freqEst);

%% ---- 结果 ----
fprintf('[5/5] 还原消息: "%s"\n', recvMsg);
if ok
    fprintf('\n  >>> 演示成功! 真实空口完整还原 <<<\n');
else
    fprintf('\n  >>> 未完全还原, 请调整天线距离/增益 <<<\n');
end

%% ---- 释放 ----
release(tx); release(rx);

%% ---- 演示图: 星座 + 相关峰 ----
figure('Name','QPSK 空口演示','Position',[60 60 1100 500],'Color','w');

subplot(1,2,1);
pIdx = params.PreambleSym + params.HeaderSym + 1;
plot(real(dg.rxSymComp(pIdx:end)), imag(dg.rxSymComp(pIdx:end)), 'b.', 'MarkerSize',6);
hold on;
ref = pskmod((0:M-1).',M);
plot(real(ref), imag(ref), 'ro', 'MarkerSize',10, 'LineWidth',1.5);
axis equal; xlim([-1.6 1.6]); ylim([-1.6 1.6]); grid on;
xlabel('I'); ylabel('Q');
title('接收星座 (蓝点=信号, 红圈=理想点)');

subplot(1,2,2);
m = abs(dg.corrMetric); m = m/max(m);
plot(m, 'b'); hold on;
xline(dg.frameStart, '--r', 'LineWidth',1.2);
xlabel('采样序号'); ylabel('归一化相关');
title('帧检测: 相关峰定位帧起点'); grid on;
xlim([1 min(length(m), 8000)]);

if ~isfolder('plots'); mkdir('plots'); end
saveas(gcf, 'plots/demo_result.png');
fprintf('\n演示图已保存: plots/demo_result.png\n');
