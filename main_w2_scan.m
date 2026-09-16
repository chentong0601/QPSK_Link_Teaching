%% ===== W2 扩展验证: 频偏/SNR 扫描 =====
% 目的: 验证同步算法在不同频偏和信噪比下的鲁棒性
% 输出: 频偏估计误差表 + BER 表 (写入 results/w2_scan.txt)
clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;

% 发射固定帧
msg = 'HELLO QPSK!';
[~, scrambler, ~] = gen_frame_sequences(params);
frameSym = tx_frame(int8(msg(:)), params, 0, 0);
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[txWave, ~] = tx_baseband(frameSym, L, rrc);
txWave = txWave/max(abs(txWave));
sigPower = mean(abs(txWave).^2); Eg = sum(rrc.^2);

% 扫描范围
fList = [0 50 100 200 300 500];    % 频偏 Hz
snrList = [0 4 8 12];              % Eb/N0 dB

fprintf('EbN0\\fInj'); fprintf('%8.0f', fList); fprintf('\n');
estTable = zeros(length(snrList), length(fList));
for si = 1:length(snrList)
    EbN0 = 10^(snrList(si)/10);
    sigma = sqrt(sigPower*Eg/(2*EbN0*bp));
    for fi = 1:length(fList)
        t = (0:length(txWave)-1).'/params.SampleRate;
        rw = txWave.*exp(1j*2*pi*fList(fi).*t);
        rw = rw + sigma*(randn(size(rw))+1j*randn(size(rw)));
        [~, ~, diag] = rx_frame(rw, params, scrambler, rrc);
        estTable(si,fi) = diag.freqEst;
    end
    fprintf('%4.0fdB ', snrList(si)); fprintf('%8.1f', estTable(si,:)); fprintf('\n');
end

% 保存结果
if ~isfolder('results'); mkdir('results'); end
save('results/w2_scan.mat','fList','snrList','estTable');
fprintf('\n已保存: results/w2_scan.mat\n');
