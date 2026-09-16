%% plot_p1_gain_sweep.m
% 自动遍历 results/p1_g*.mat，画 RxGain vs 5 指标对照图
% 用途：闭环证明 §6.4 ADC 饱和诊断 + §6.6 处置恢复
% 跑法：
%   cd D:\ChenTong\SDR_project\QPSK_Link_Teaching
%   plot_p1_gain_sweep
% 输出：plots/p1_gain_sweep.png  + 命令窗 4 指标表
function plot_p1_gain_sweep()
    cfg;
    resDir = fullfile('results');
    files = dir(fullfile(resDir, 'p1_g*.mat'));
    if isempty(files)
        error('未找到 results/p1_g*.mat，请先按 §6.6 跑完至少两档 (gain=30/23/10/0)');
    end

    % 收集
    G = []; N = []; PEAK = []; NOISE = []; DYN = []; OCC = [];
    EDGE = []; CLIP = []; BW3 = []; OCCBW = [];
    FNAMES = {};
    for k = 1:length(files)
        S = load(fullfile(resDir, files(k).name));
        if ~isfield(S, 'noiseFloor'), continue; end
        G(end+1)    = S.CFG.RxGain;
        % 0.5s 数据（gain=30 是粗扫 0.5s; gain=23 取长抓前 0.5s）
        if isfield(S, 'scanRes') && ~isempty(S.scanRes)
            % 找 ch6
            idx = find(cellfun(@(n) contains(lower(n),'ch6'), {S.scanRes.name}), 1);
            if isempty(idx)
                [~, idx] = max([S.scanRes.pwrDbm]);
            end
            x = S.scanRes(idx).iq;
            fs = S.CFG.SampleRate;
            tag = sprintf('g%d粗扫ch6', round(G(end)));
        else
            x = S.xLong(1:round(0.5*S.CFG.SampleRate));
            fs = S.CFG.SampleRate;
            tag = sprintf('g%d长抓前0.5s', round(G(end)));
        end
        absx = abs(x);
        N(end+1)    = length(x);
        PEAK(end+1) = max(absx);
        NOISE(end+1)= median(absx);
        EDGE(end+1) = mean(absx>0.95) / max(mean(absx>0.85)-mean(absx>0.95), eps);
        CLIP(end+1) = mean(absx>1.0)*100;
        % PSD
        Nfft = length(x);
        psd = 10*log10(fftshift(abs(fft(x)).^2)/(Nfft*fs)+1e-30);
        flr = median(psd);
        pk  = max(psd);
        DYN(end+1) = pk - flr;
        bw3 = sum(psd>pk-3)*(fs/Nfft)/1e3;
        BW3(end+1) = bw3;
        occ = sum(psd>flr+10)*(fs/Nfft)/1e3;
        OCCBW(end+1) = occ;
        OCC(end+1)  = mean(absx>0.05)*100;
        FNAMES{end+1} = [files(k).name ' (' tag ')'];
    end
    [G, ord] = sort(G);
    PEAK=PEAK(ord); NOISE=NOISE(ord); DYN=DYN(ord); OCC=OCC(ord);
    EDGE=EDGE(ord); CLIP=CLIP(ord); BW3=BW3(ord); OCCBW=OCCBW(ord);
    FNAMES=FNAMES(ord);

    % 命令窗汇总
    fprintf('\n=== P1 增益扫描对照 (fc=2437MHz, 0.5s 捕获) ===\n');
    fprintf('%-7s %-8s %-9s %-9s %-9s %-8s %-10s %-9s\n', ...
        'Gain', '|x|max', 'edgeRatio', 'clip%', 'noiseFloor', 'dyn(dB)', 'occ%(>0.05)', 'occBW(kHz)');
    for k=1:length(G)
        fprintf('%-7.0f %-8.3f %-9.3f %-9.3f %-9.3f %-8.2f %-10.2f %-9.1f   %s\n', ...
            G(k), PEAK(k), EDGE(k), CLIP(k), NOISE(k), DYN(k), OCC(k), OCCBW(k), FNAMES{k});
    end

    % 画图：5 子图
    figure('Position',[100 100 1100 700],'Color','w');
    titles = {'峰值幅度 |x|max (饱和→1.414)', ...
              '边缘堆积比 (饱和>1.2)', ...
              '|x|>1.0 占比 % (硬削顶)', ...
              '动态范围 dB (OFDM 真实~30)', ...
              '时间占用度 % (>0.05)'};
    Y      = {PEAK, EDGE, CLIP, DYN, OCC};
    Ymax   = [1.5 2.5 10 max(35, max(DYN)+5) 100];
    thresh = [1.0 1.2 0.1 0 0];

    for k=1:5
        subplot(2,3,k);
        plot(G, Y{k}, 'o-', 'LineWidth',1.5, 'MarkerSize',10, 'MarkerFaceColor','auto');
        hold on; yline(thresh(k), 'r--', 'LineWidth',1);
        xlabel('RxGain (dB)'); ylabel(titles{k}); title(titles{k});
        grid on; xlim([min(G)-2 max(G)+2]); ylim([0 Ymax(k)]);
        for i=1:length(G)
            text(G(i), Y{k}(i), sprintf('  %s', FNAMES{i}), 'FontSize',7, 'VerticalAlignment','bottom');
        end
    end
    sgtitle('P1 §6.6 跨 RxGain 扫描 (fc=2437MHz, 0.5s 捕获) — ADC 饱和恢复曲线', 'FontWeight','bold');

    outFn = 'plots/p1_gain_sweep.png';
    if ~exist('plots','dir'), mkdir('plots'); end
    saveas(gcf, outFn);
    fprintf('\n图已保存: %s\n', outFn);
end