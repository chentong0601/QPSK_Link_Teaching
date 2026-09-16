%% main_w7_compare.m
% W6 vs W7 对比实验 —— DD-PLL 相位跟踪的量化收益 (报告核心图)
%
% 对比项:
%   (a) 解帧成功率 vs Eb/N0   (走生产路径 rx_receiver, 满载荷 62 字节)
%   (b) BER vs Eb/N0          (理想切分, 逐比特比对, 附理论 QPSK 曲线)
% 产出: plots/w7_compare.png
%
% 用法: matlab -batch "main_w7_compare"

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);
Nsym = params.PreambleSym + params.HeaderSym + params.PayloadSym;
ref  = pskmod((0:M-1).', M);

EbN0_list = [4 6 8 10 12 14 16];
freqOffset = 320;

fprintf('\n################################################################\n');
fprintf('#   W6 vs W7 对比 (DD-PLL 相位跟踪)                             #\n');
fprintf('#   满载荷 62 字节, 注入频偏 %d Hz                               #\n', freqOffset);
fprintf('################################################################\n\n');

fsr  = nan(numel(EbN0_list), 2);   % [W6 W7]
ber  = nan(numel(EbN0_list), 2);
berT = nan(numel(EbN0_list), 1);

%% ===== (a) 解帧成功率 (生产路径) =====
fprintf('--- (a) 解帧成功率 vs Eb/N0 (rx_receiver, 20 帧 x 2 次) ---\n');
fprintf('%8s | %12s | %12s\n', 'Eb/N0', 'W6 无PLL', 'W7 有PLL');
fprintf('%s\n', repmat('-', 1, 38));
nF = 20; nRep = 2;
for ei = 1:numel(EbN0_list)
    dB = EbN0_list(ei);
    for mode = 1:2
        params.PhaseTrack = (mode == 2);
        okTot = 0; nTot = 0;
        for tr = 1:nRep
            rng(500*tr + dB);
            cw = []; msgs = {};
            for k = 1:nF
                m = [sprintf('PKT-%03d-', k-1) repmat('X', 1, 54)];
                msgs{k} = m;
                fS = tx_frame(int8(m(:)), params, 0, mod(k-1,256));
                [w, ~] = tx_baseband(fS, L, rrc);
                w = w * 0.9/max(abs(w));
                if k == 1, Es = L*mean(abs(w).^2); end
                cw = [cw; w; zeros(80,1)]; %#ok<AGROW>
            end
            nn = (0:length(cw)-1).';
            cw = cw .* exp(1j*2*pi*freqOffset*nn/params.SampleRate);
            sg = sqrt(Es/(2*10^(dB/10)*bp));
            cw = cw + sg*(randn(size(cw))+1j*randn(size(cw)));
            [pbs, ~] = rx_receiver(cw, params, scrambler, rrc, nF);
            for i = 1:length(pbs)
                t = strtrim(char(pbs{i}(:)).');
                if any(strcmp(t, msgs)), okTot = okTot + 1; end
            end
            nTot = nTot + nF;
        end
        fsr(ei, mode) = okTot/nTot;
    end
    fprintf('%6d dB | %11.1f%% | %11.1f%%\n', dB, fsr(ei,1)*100, fsr(ei,2)*100);
end

%% ===== (b) BER (理想切分, 逐比特) =====
fprintf('\n--- (b) BER vs Eb/N0 (理想切分, 200 次/点) ---\n');
fprintf('%8s | %12s | %12s | %12s\n', 'Eb/N0', 'W6 无PLL', 'W7 有PLL', '理论QPSK');
fprintf('%s\n', repmat('-', 1, 54));
NT = 200;
msg = [sprintf('PKT-%03d-', 0) repmat('X',1,54)];
fSym = tx_frame(int8(msg(:)), params, 0, 0);
sIdxTx = pskdemod(fSym, M);
bTx = reshape(de2bi(sIdxTx, bp, 'left-msb').', [], 1);
for ei = 1:numel(EbN0_list)
    dB = EbN0_list(ei);
    for mode = 1:2
        params.PhaseTrack = (mode == 2);
        acc = 0;
        for tr = 1:NT
            rng(9000+tr);
            [w,~] = tx_baseband(fSym, L, rrc);
            w = w*0.9/max(abs(w));
            if tr==1, Es2 = L*mean(abs(w).^2); end
            nn = (0:length(w)-1).';
            rx = w .* exp(1j*2*pi*freqOffset*nn/params.SampleRate);
            sg = sqrt(Es2/(2*10^(dB/10)*bp));
            rx = rx + sg*(randn(size(rx))+1j*randn(size(rx)));
            try
                [~, ~, dg] = rx_frame(rx, params, scrambler, rrc);
                if params.PhaseTrack, x = dg.rxTracked; else, x = dg.rxSymComp; end
                [~, mi] = min(abs(x.' - ref).^2, [], 1);
                bRx = reshape(de2bi((mi-1).', bp, 'left-msb').', [], 1);
                acc = acc + mean(bTx ~= bRx);
            catch
                acc = acc + 0.5;      % 同步失败按 0.5 计
            end
        end
        ber(ei, mode) = acc/NT;
    end
    % 理论 QPSK (Gray, AWGN, 相干): Q(sqrt(2*Eb/N0))
    berT(ei) = qfunc(sqrt(2*10^(dB/10)));
    fprintf('%6d dB | %12.3e | %12.3e | %12.3e\n', dB, ber(ei,1), ber(ei,2), berT(ei));
end

%% ===== 绘图 =====
f = figure('Position',[80 80 980 430],'Color','w');

subplot(1,2,1);
plot(EbN0_list, fsr(:,1)*100, '-o', 'LineWidth',1.8, 'MarkerSize',7, ...
     'MarkerFaceColor','#F0997B','Color','#993C1D'); hold on;
plot(EbN0_list, fsr(:,2)*100, '-s', 'LineWidth',1.8, 'MarkerSize',7, ...
     'MarkerFaceColor','#5DCAA5','Color','#0F6E56');
grid on; box on;
xlabel('E_b/N_0 (dB)','FontSize',11); ylabel('解帧成功率 (%)','FontSize',11);
legend({'W6 无相位跟踪','W7 有 DD-PLL'},'Location','southeast','FontSize',10);
title('(a) 解帧成功率 (满载荷 62 字节)','FontSize',11);
ylim([-5 105]);

subplot(1,2,2);
semilogy(EbN0_list, max(ber(:,1),1e-4), '-o', 'LineWidth',1.8, 'MarkerSize',7, ...
     'MarkerFaceColor','#F0997B','Color','#993C1D'); hold on;
semilogy(EbN0_list, max(ber(:,2),1e-4), '-s', 'LineWidth',1.8, 'MarkerSize',7, ...
     'MarkerFaceColor','#5DCAA5','Color','#0F6E56');
semilogy(EbN0_list, max(berT,1e-4), '--', 'LineWidth',1.4, 'Color','#5F5E5A');
grid on; box on;
xlabel('E_b/N_0 (dB)','FontSize',11); ylabel('BER','FontSize',11);
legend({'W6 无相位跟踪','W7 有 DD-PLL','理论 QPSK'},'Location','southwest','FontSize',10);
title('(b) BER (理想切分)','FontSize',11);

sgtitle('W7 相位跟踪 (DD-PLL) 的量化收益','FontSize',12);
if ~isfolder('plots'), mkdir('plots'); end
saveas(f, fullfile('plots','w7_compare.png'));
fprintf('\n[OK] 对比图已保存 plots/w7_compare.png\n');

% 保存数据
if ~isfolder('results'), mkdir('results'); end
save('results/w7_compare.mat','EbN0_list','fsr','ber','berT');
fprintf('[OK] 数据已保存 results/w7_compare.mat\n\n');
