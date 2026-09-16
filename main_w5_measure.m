%% ===== W5: 硬件实测数据采集 (增益扫描 + 重复性) =====
% 目的: 采集报告所需实测数据
%   实验E4: RxGain 扫描 -> 不同接收增益下的解调成功率与频偏估计
%   实验E5: 重复性 -> 固定配置多次运行, 评估同步算法稳定性
% 用法: 在 MATLAB GUI 运行 (需硬件)
% 准备: TX/RX 两根天线, 固定距离(建议 15~20cm)
% 输出: results/w5_measure.mat + plots/w5_measure.png

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M=params.M; bp=params.bitsPerSym; L=params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

msg = 'HELLO QPSK!';
frameSym = tx_frame(int8(msg(:)), params, 0, 0);
[txWave, ~] = tx_baseband(frameSym, L, rrc);
txWave = txWave * 0.9/max(abs(txWave));

%% ---- 启动发射 ----
tx = sdrtx('Pluto');
tx.CenterFrequency = params.CenterFrequency;
tx.BasebandSampleRate = params.SampleRate;
tx.Gain = params.TxGain;
tx.OutputDataType = 'double';
transmitRepeat(tx, txWave);
fprintf('[OK] 发射中 (TxGain=%d dB), 开始实测...\n', params.TxGain);

%% ---- 接收对象 ----
rx = sdrrx('Pluto');
rx.CenterFrequency = params.CenterFrequency;
rx.BasebandSampleRate = params.SampleRate;
rx.GainSource = 'Manual';
rx.SamplesPerFrame = params.RxFrames;
rx.OutputDataType = 'double';

%% ================= 实验 E4: RxGain 扫描 =================
gainList = [20 25 30 35 40 45 50];
nG = length(gainList);
passRate = zeros(nG,1);
freqEst  = nan(nG,1);
rxPow    = nan(nG,1);

fprintf('\n===== 实验E4: RxGain 扫描 (每档5次) =====\n');
fprintf('RxGain | 成功率 | 频偏(Hz) | 接收功率\n');
for gi = 1:nG
    rx.Gain = gainList(gi);
    nOk = 0; fList = nan(5,1); pList = nan(5,1); kf = 0; kp = 0;
    for trial = 1:5
        d = rx();
        kp = kp + 1; pList(kp) = mean(abs(d).^2);
        try
            [pb, ~, dg] = rx_frame(d, params, scrambler, rrc);
            if strcmp(char(pb(:)).', msg), nOk = nOk + 1; end
            kf = kf + 1; fList(kf) = dg.freqEst;
        catch
        end
    end
    fList = fList(1:kf); pList = pList(1:kp);
    passRate(gi) = nOk/5;
    if ~isempty(fList), freqEst(gi) = mean(fList); end
    rxPow(gi) = mean(pList);
    fprintf('%5d  |  %3d%%  | %8.1f | %.2e\n', ...
            gainList(gi), round(100*nOk/5), freqEst(gi), rxPow(gi));
end

%% ================= 实验 E5: 重复性 =================
rx.Gain = 40;
nRep = 10; fRep = nan(nRep,1); okRep = zeros(nRep,1);
fprintf('\n===== 实验E5: 重复性 (RxGain=40, %d 次) =====\n', nRep);
for i = 1:nRep
    d = rx();
    try
        [pb, ~, dg] = rx_frame(d, params, scrambler, rrc);
        fRep(i) = dg.freqEst;
        if strcmp(char(pb(:)).', msg), okRep(i) = 1; end
    catch
    end
end
fprintf('成功率 = %d/%d, 频偏均值 = %.1f Hz, 标准差 = %.1f Hz\n', ...
        sum(okRep), nRep, mean(fRep,'omitnan'), std(fRep,'omitnan'));

%% ---- 停止发射 ----
release(tx); release(rx);
fprintf('\n[OK] 已停止发射\n');

%% ---- 保存 + 画图 ----
if ~isfolder('results'); mkdir('results'); end
gainTag = strjoin(arrayfun(@(g) sprintf('%d',round(g)), gainList, 'UniformOutput',false), '-');
save(sprintf('results/w5_g%s.mat', gainTag),'gainList','passRate','freqEst','rxPow','fRep','okRep');
fprintf('[OK] 数据已保存: results/w5_g%s.mat\n', gainTag);

figure('Position',[80 80 1000 400],'Color','w');
subplot(1,2,1);
bar(gainList, 100*passRate); grid on; ylim([0 105]);
xlabel('RxGain (dB)'); ylabel('解调成功率 (%)'); title('实验E4: 接收增益 vs 成功率');
subplot(1,2,2);
plot(gainList, freqEst, 'o-'); grid on;
xlabel('RxGain (dB)'); ylabel('频偏估计 (Hz)'); title('实验E4: 频偏估计 vs 接收增益');
if ~isfolder('plots'); mkdir('plots'); end
saveas(gcf,'plots/w5_measure.png');
fprintf('[OK] 图已保存: plots/w5_measure.png\n');
