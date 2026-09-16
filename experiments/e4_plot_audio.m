function e4_plot_audio(link, txAudio, rxAudio, fs, metrics)
%E4_PLOT_AUDIO  语音传输对比图 (纯 MATLAB 实现, 四联)
%
%   ① 波形叠加 (发蓝收红)      —— 看偏离
%   ② 波形并排                  —— 看形态
%   ③ 语谱图并排 (spectrogram)  —— 看哪个频段/时段受损
%   ④ 分段 SNR 时序             —— 把损伤量化到时间轴
%
%   另含【自动块级循环移位检测】: transmitRepeat 循环发射 + 采集起点不在开头时,
%   接收可能是发送的循环移位, 此时自动对齐后作图, 避免误判为"传输错误"。
%
%   输入:
%     link     : 链路标识
%     txAudio  : 发送音频 (-1..1)
%     rxAudio  : 接收音频 (-1..1)
%     fs       : 采样率
%     metrics  : struct, 可选字段 rho / segSNR (仅用于标题对照)
%
%   输出: plots/e4/<link>_audio.png
%
%   依赖: Signal Processing Toolbox (spectrogram); 无则降级为不画语谱图。

    txAudio = double(txAudio(:));
    rxAudio = double(rxAudio(:));
    n = min(numel(txAudio), numel(rxAudio));
    txAudio = txAudio(1:n); rxAudio = rxAudio(1:n);
    t = (0:n-1).' / fs;

    % ---- 块级循环移位检测 ----
    blk = max(1, round(fs * 0.1));           % 100 ms
    nblk = max(1, floor(n / blk));
    bestK = 0; bestC = -2;
    for k = -min(nblk, 60) : min(nblk, 60)
        shifted = circshift(rxAudio, -k*blk);
        c = localCorr(txAudio, shifted);
        if c > bestC, bestC = c; bestK = k; end
    end
    cRaw = localCorr(txAudio, rxAudio);
    doAlign = (bestK ~= 0) && (bestC > 0.5);
    if doAlign
        rxShow = circshift(rxAudio, -bestK*blk);
    else
        rxShow = rxAudio;
    end
    hasSpec = exist('spectrogram', 'file') == 2 || exist('spectrogram', 'builtin') == 5;

    BLUE = [0.12 0.37 0.75];
    RED  = [0.82 0.23 0.23];

    fig = figure('Position', [60 60 1100 820], 'Color', 'w', 'Visible', 'on');

    % ① 波形叠加
    ax1 = subplot(4,1,1);
    plot(ax1, t, txAudio, 'Color', BLUE, 'LineWidth', 0.6); hold(ax1,'on');
    plot(ax1, t, rxShow,   'Color', RED,  'LineWidth', 0.6);
    grid(ax1, 'on'); set(ax1, 'GridAlpha', 0.2);
    if doAlign
        tag = sprintf('已按最佳块移位对齐 (%+d 块; 原始相关 %.4f)', bestK, cRaw);
    else
        tag = sprintf('直接对齐 (相关 %.4f)', cRaw);
    end
    title(ax1, ['① 波形叠加对比 (发送=蓝, 接收=红) —— ' tag], 'FontSize', 11);
    ylabel(ax1, '幅度'); xlabel(ax1, '时间 (s)');
    legend(ax1, {'发送','接收'}, 'Location', 'northeast', 'FontSize', 9);

    % ② 波形并排
    ax2 = subplot(4,1,2);
    plot(ax2, t, txAudio, 'Color', BLUE, 'LineWidth', 0.6); hold(ax2,'on');
    plot(ax2, t, rxShow - 2.4, 'Color', RED, 'LineWidth', 0.6);
    grid(ax2, 'on'); set(ax2, 'GridAlpha', 0.2);
    title(ax2, '② 波形并排 (上=发送, 下=接收, 已下移 2.4 便于对照)', 'FontSize', 11);
    xlabel(ax2, '时间 (s)'); set(ax2, 'YTick', []);

    % ③ 语谱图并排
    if hasSpec
        ax3 = subplot(4,2,5);
        try
            spectrogram(txAudio, 256, 192, 256, fs, 'yaxis');
        catch
            spectrogram(txAudio, 256, 192, 256, fs);
        end
        title(ax3, '③ 发送 语谱图', 'FontSize', 11, 'Color', BLUE);
        ax4 = subplot(4,2,6);
        try
            spectrogram(rxShow, 256, 192, 256, fs, 'yaxis');
        catch
            spectrogram(rxShow, 256, 192, 256, fs);
        end
        title(ax4, '③ 接收 语谱图', 'FontSize', 11, 'Color', RED);
    else
        annotation(fig, 'textbox', [0.3 0.30 0.4 0.05], 'String', ...
            '未找到 spectrogram (需 Signal Processing Toolbox), 跳过语谱图', ...
            'EdgeColor', 'none', 'HorizontalAlignment', 'center');
    end

    % ④ 分段 SNR 时序
    ax5 = subplot(4,1,4);
    nSeg = 20;
    segLen = max(1, floor(n / nSeg));
    vals = nan(1, nSeg);
    for i = 1:nSeg
        a = (i-1)*segLen + 1; b = min(i*segLen, n);
        if b < a, continue; end
        e = txAudio(a:b) - rxShow(a:b);
        pe = sum(e.^2); ps = sum(txAudio(a:b).^2);
        if pe < 1e-12
            vals(i) = 60;
        else
            vals(i) = 10*log10(max(ps,1e-12) / pe);
        end
    end
    bar(ax5, 1:nSeg, vals, 'FaceColor', [0.50 0.70 0.90], 'EdgeColor', BLUE, 'LineWidth', 0.6);
    hold(ax5, 'on');
    med = median(vals(~isnan(vals)));
    yline(ax5, med, '--', sprintf('中位数 %.1f dB', med), 'Color', RED, ...
          'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');
    grid(ax5, 'on'); set(ax5, 'GridAlpha', 0.2);
    title(ax5, '④ 分段 SNR 时序 (哪一段被破坏, 一眼可见)', 'FontSize', 11);
    xlabel(ax5, sprintf('时间分段 (共 %d 段)', nSeg)); ylabel(ax5, 'SNR (dB)');

    % ---- 总标题 ----
    rhoShow = localCorr(txAudio, rxShow);
    segMed  = med;
    sup = sprintf('E4-AUD 语音端到端传输   [%s]   对齐后相关 %.4f   分段SNR %.2f dB   %.2f s', ...
                  link, rhoShow, segMed, n/fs);
    if doAlign
        rhoRec = NaN;
        if isfield(metrics, 'rho'), rhoRec = double(metrics.rho); end
        sup = sprintf(['%s\n(注: 记录的相关 %.4f 为未对齐值; 已按最佳块移位 %+d 块校正)'], ...
                      sup, rhoRec, bestK);
    end
    sgtitle(sup, 'FontSize', 12);

    % ---- 保存 ----
    outdir = fullfile('plots', 'e4');
    if ~isfolder(outdir), mkdir(outdir); end
    fn = fullfile(outdir, sprintf('%s_audio.png', link));
    try
        exportgraphics(fig, fn, 'Resolution', 130);
    catch
        saveas(fig, fn);
    end
    close(fig);
    fprintf('[OK] 语音对比图: %s\n', fn);
end

function r = localCorr(a, b)
%LOCALCORR  归一化互相关系数 (不依赖 Statistics Toolbox)
    a = a(:) - mean(a); b = b(:) - mean(b);
    d = sqrt(sum(a.^2) * sum(b.^2));
    if d < 1e-12, r = NaN; else, r = sum(a.*b) / d; end
end
