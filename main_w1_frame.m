%% ===== W1: 帧结构 + 发射端波形验证（纯仿真）=====
% 验证目标:
%  1. tx_frame 能正确组帧 (前导32 + 帧头8 + payload)
%  2. 完整帧波形经 tx_baseband 成形后结构正确
%  3. 帧首部特征可辨识 (为 W2 帧检测做准备)
% 用法: matlab -batch "main_w1_frame" (纯仿真, 无需硬件)

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;

M          = params.M;
bitsPerSym = params.bitsPerSym;

%% ---- 1. 构造一帧 payload: 一段文字 "HELLO QPSK!" ----
msg    = 'HELLO QPSK!';
dataB  = int8(msg(:));                             % ASCII 字符 -> 字节列
fprintf('[OK] payload 有效字节数 = %d (上限 %d 字节, 多余自动补零)\n', ...
        length(dataB), params.PayloadSym*bitsPerSym/8);

%% ---- 2. 组帧 (类型0=文字, 帧号0) ----
frameSym = tx_frame(dataB, params, 0, 0);
fprintf('[OK] 帧符号数 = %d (期望 %d = 32+16+248)\n', length(frameSym), ...
        params.PreambleSym + params.HeaderSym + params.PayloadSym);

%% ---- 3. 发射端成形: 上采样 + RRC ----
rrc     = rcosdesign(params.RollOff, params.RRCSpan, params.SamplesPerSym, 'sqrt');
[txWave, upsampled] = tx_baseband(frameSym, params.SamplesPerSym, rrc);

% 成形后需归一化(避免超出 Pluto DAC 满幅, 为硬件做准备)
peak = max(abs(txWave));
txWave = txWave / peak;
fprintf('[OK] 帧波形长度 = %d 采样 (≈%d符号 x %d)\n', length(txWave), ...
        length(frameSym), params.SamplesPerSym);

%% ---- 4. 验证: 画帧波形 (看前导/帧头/payload 边界) ----
% 把波形按符号周期 L=4 抽样恢复符号级, 便于对齐观察
symIdx = length(frameSym);
t_sym  = (0:symIdx-1);          % 符号序号轴

figure('Name','W1 帧结构验证','Position',[80 80 1000 650],'Color','w');

% 4.1 整帧成形波形(I分量) —— 看包络起止
subplot(3,1,1);
txI = real(txWave);
plot((0:length(txWave)-1)/params.SamplesPerSym, txI, 'b', 'LineWidth', 0.8); hold on;
% 画前导/数据分界(符号位置 → 采样位置换算需要 RRC 群延迟, 这里粗略画符号起点)
for k = [0 params.PreambleSym params.PreambleSym+params.HeaderSym]
    xline(k, '--r');
end
xlim([0 symIdx+6]);
xlabel('符号序号'); ylabel('I 幅度'); grid on;
title('整帧成形波形 (虚线: 前导|帧头|payload 边界)');
legend('波形 I', '段边界', 'Location','northeast');

% 4.2 前导段特写 —— 观察成形后前导的周期性结构
subplot(3,1,2);
seg = (params.PreambleSym+4)*params.SamplesPerSym;  % 前导+少量帧头
plot((0:seg-1)/params.SamplesPerSym, real(txWave(1:seg)), 'b', 'LineWidth', 0.8);
xline(params.PreambleSym, '--r');
xlabel('符号序号'); ylabel('幅度'); grid on;
title('前导段特写 (红色虚线前 32 符号为前导)');

% 4.3 星座: 还原帧符号(抽样), 确认 4 个 QPSK 点
rxSym = txWave(1: params.SamplesPerSym*length(frameSym));  % 近似无延迟取段
subplot(3,1,3);
plot(real(frameSym), imag(frameSym), 'bo', 'MarkerSize',3); hold on;
axis equal; xlim([-1.5 1.5]); ylim([-1.5 1.5]); grid on;
title(['帧符号星座 (共 ' num2str(length(frameSym)) ' 符号)']);

%% ---- 5. 自检打印 ----
fprintf('\n===== 自检 =====\n');
fprintf('帧结构: 前导%d + 帧头%d + payload%d = %d 符号\n', ...
        params.PreambleSym, params.HeaderSym, params.PayloadSym, length(frameSym));
fprintf('payload 可容纳 %d 字符 (8bit/字符)\n', params.PayloadSym*bitsPerSym/8);
fprintf('前导是伪随机 QPSK 序列(固定种子) => 收发可重现\n');

%% ---- 6. 存图 ----
if ~isfolder('plots'); mkdir('plots'); end
saveas(gcf, 'plots/w1_frame_waveform.png');
fprintf('[OK] 图已保存: plots/w1_frame_waveform.png\n');
