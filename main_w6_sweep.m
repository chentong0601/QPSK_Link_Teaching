%% ===== W6 补充: 连续接收机 解帧成功率扫描 (修正版) =====
% 目的: 给出接收机的 解帧成功率 vs Eb/N0 曲线
%
% ★ 修正记录 (2026-09-10, 外部评审核对后):
%   1) 原版统计 stats.nDecoded (解出的帧数) 而非【正确】帧数 => 指标虚高。
%      本版改为逐帧比对解出的 payload 文本与发送文本。
%   2) 原版只用 10 字节短载荷。实测发现: 误码集中在帧尾, 而短消息只占载荷区
%      前 40 个符号, 其余错误落在被丢弃的补零区 => 短载荷系统性掩盖误码。
%      本版同时给出【短载荷】与【满载荷】两条曲线。
%   3) 噪声按实际符号能量标定 (原版隐含 Es=1, 使 Eb/N0 标称偏高约 1.83 dB)。
%   详见 notes/exp_baseline_metrics.md §E4/E5/E6
% 用法: matlab -batch "main_w6_sweep"

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
bp = params.bitsPerSym; L = params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

nF = 20; freqOffset = 320; EbN0dB_list = 2:2:18; nRep = 3;

fprintf('===== 连续接收机 解帧成功率 vs Eb/N0 (修正版) =====\n');
fprintf('%d 帧/次, %d 次重复, 频偏 %d Hz\n\n', nF, nRep, freqOffset);
fprintf('%8s | %14s | %14s\n', 'Eb/N0', '短载荷(10B)', '满载荷(62B)');
fprintf('%s\n', repmat('-', 1, 46));

res = zeros(length(EbN0dB_list), 2);
for ei = 1:length(EbN0dB_list)
    EbN0dB = EbN0dB_list(ei);
    for mode = 1:2
        if mode == 1, nByte = 10; else, nByte = 62; end
        totOK = 0; totN = 0;
        for tr = 1:nRep
            rng(100*tr + EbN0dB);
            contWave = []; msgs = {};
            for k = 1:nF
                base = sprintf('PKT-%03d-', k-1);          % 8 字符
                if nByte == 10
                    m = [base 'OK'];
                else
                    m = [base repmat('X', 1, nByte-8)];
                end
                msgs{k} = m;
                fSym = tx_frame(int8(m(:)), params, 0, mod(k-1,256));
                [w, ~] = tx_baseband(fSym, L, rrc);
                w = w * 0.9/max(abs(w));
                if k == 1, Es = L * mean(abs(w).^2); end
                contWave = [contWave; w; zeros(80,1)]; %#ok<AGROW>
            end
            % 频偏
            n = (0:length(contWave)-1).';
            contWave = contWave .* exp(1j*2*pi*freqOffset*n/params.SampleRate);
            % 噪声 (按单帧实际符号能量标定)
            sigma = sqrt(Es/(2*10^(EbN0dB/10)*bp));
            contWave = contWave + sigma*(randn(size(contWave))+1j*randn(size(contWave)));

            [pbs, ~] = rx_receiver(contWave, params, scrambler, rrc, nF);
            for i = 1:length(pbs)
                t = strtrim(char(pbs{i}(:)).');
                if any(strcmp(t, msgs)), totOK = totOK + 1; end
            end
            totN = totN + nF;
        end
        res(ei, mode) = totOK / totN;
    end
    fprintf('%6d dB | %13.1f%% | %13.1f%%\n', EbN0dB, res(ei,1)*100, res(ei,2)*100);
end

fprintf('\n[结论] 短载荷曲线明显偏乐观; 应以【满载荷】曲线作为真实指标。\n');

%% ---- 绘图 ----
f = figure('Position',[100 100 740 480],'Color','w');
plot(EbN0dB_list, res(:,1)*100, '-o', 'LineWidth',2, 'MarkerSize',7, ...
     'MarkerFaceColor','#85B7EB', 'Color','#185FA5'); hold on;
plot(EbN0dB_list, res(:,2)*100, '-s', 'LineWidth',2, 'MarkerSize',7, ...
     'MarkerFaceColor','#F0997B', 'Color','#993C1D');
grid on; box on;
xlabel('E_b/N_0 (dB)', 'FontSize',12);
ylabel('解帧成功率 (%)', 'FontSize',12);
legend({'短载荷 10 字节','满载荷 62 字节'}, 'Location','southeast', 'FontSize',11);
title(sprintf('连续接收机解帧成功率 (%d 帧/次, 频偏 %d Hz)', nF, freqOffset), 'FontSize',12);
ylim([-5 105]); xlim([min(EbN0dB_list)-0.5 max(EbN0dB_list)+0.5]);
if ~isfolder('plots'), mkdir('plots'); end
saveas(f, fullfile('plots','w6_frame_success.png'));
fprintf('[OK] 曲线已保存 plots/w6_frame_success.png\n');
