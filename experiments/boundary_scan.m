%experiments/boundary_scan.m  边界扫描：SNR 与频偏对单帧成功率的影响
%  用途: 在没有硬件的仿真环境中, 评估 P6a 测得 p 后视频帧完成率的真实边界
%  用法: matlab -batch "experiments/boundary_scan"
%
% ★ 这个脚本演示了 P6 教程中 "p >= 0.99" 阈值的来源

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params; M = params.M; bp = params.bitsPerSym;
L = params.SamplesPerSym; Rs = params.SymbolRate;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[preambleSym, scrambler, ~, ~] = frame_sequences_cached(params);
preSym = preambleSym;
Nsym = params.PreambleSym + params.HeaderSym + params.PayloadSym;

% 组一帧已知载荷 (56 字节, < 62 上限)
payload = uint8([sprintf('SCAN-%03d-', 0), repmat('X', 1, 47)].');
fSym = tx_frame(payload, params, 0, 0);
[w, ~] = tx_baseband(fSym, L, rrc);
w = w * 0.9 / max(abs(w));
Es = L * mean(abs(w).^2);

% SNR 扫描 (4~18 dB)
SNRs = 4:2:18;
nT = 200;  % 每点蒙特卡洛
pList = zeros(size(SNRs));
for i = 1:numel(SNRs)
    sg = sqrt(Es / (2 * 10^(SNRs(i)/10) * bp));
    nOK = 0; nUni = 0;
    for tr = 1:nT
        rng(90000 + tr*7 + i*1000);
        nn = (0:numel(w)-1).';
        rx = w .* exp(1j*2*pi*320*nn/params.SampleRate) + sg*(randn(size(w))+1j*randn(size(w)));
        mf = conv(rx, rrc); peak = length(rrc);
        rs = mf(peak:L:peak + (Nsym-1)*L).';   % 列向量
        % 仅用前导段做相关检测 (与 rx_frame 内部一致)
        rsPre = rs(1:params.PreambleSym);
        rho = abs(sum(rsPre .* conj(preSym)));
        if rho > 0.60
            [pb, hdr] = rx_frame(rx, params, scrambler, rrc);
            if hdr.crcOK && hdr.frameType==0
                nOK = nOK + 1;
            end
        end
    end
    pList(i) = nOK / nT;
end

fprintf('\n===== SNR vs p (200 trials/SNR) =====\n');
fprintf('  Eb/N0(dB) | 单帧成功率 p\n');
for i = 1:numel(SNRs)
    fprintf('     %4d   |  %.4f\n', SNRs(i), pList(i));
end

% 视频帧完成率 (假设 176x144 Q50, 47 片)
fprintf('\n===== 视频帧完成率 (176x144 Q50, 47 片) =====\n');
fprintf('  Eb/N0(dB) | 单帧 p | 视频帧完成率 (p^47)\n');
for i = 1:numel(SNRs)
    fprintf('     %4d   | %.4f | %6.1f%%\n', SNRs(i), pList(i), pList(i)^47*100);
end

% 画图
figure('Position',[100 100 700 400]);
subplot(1,2,1);
plot(SNRs, pList*100, 'o-', 'LineWidth', 2, 'MarkerSize', 8);
grid on; xlabel('Eb/N0 (dB)'); ylabel('单帧成功率 p (%)');
title('物理层单帧成功率 vs SNR');
ylim([0 105]); yline(99, 'r--', 'p=0.99 门槛', 'FontSize', 10);

subplot(1,2,2);
plot(SNRs, pList.^47*100, 's-', 'LineWidth', 2, 'MarkerSize', 8);
grid on; xlabel('Eb/N0 (dB)'); ylabel('视频帧完成率 (%)');
title('视频帧完成率 vs SNR (47 片, 全到才解)');
ylim([0 105]); yline(50, 'r--', '50% 实用门槛', 'FontSize', 10);

saveas(gcf, 'plots/boundary_scan.png');
fprintf('\n[OK] 图已保存 plots/boundary_scan.png\n');