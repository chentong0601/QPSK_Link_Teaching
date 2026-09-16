function e4_plot_text(link, txBytes, rxBytes, metrics)
%E4_PLOT_TEXT  文字传输对比图 (纯 MATLAB 实现)
%
%   只保留两部分: ① 逐字节状态条  ② 发送/接收文本并排
%   结论压缩进标题, 便于一眼看出结果。
%
%   输入:
%     link     : 链路标识 ('sim'/'coax'/'short'/'long'), 用于标题与文件名
%     txBytes  : uint8 发送字节流
%     rxBytes  : uint8 接收字节流
%     metrics  : struct, 需含 charOK (可选 byteOK)
%
%   输出: plots/e4/<link>_text.png
%
%   用法(在业务脚本内): e4_plot_text(CFG.link, txBytes, rxBytes, metrics);

    txBytes = uint8(txBytes(:));
    rxBytes = uint8(rxBytes(:));
    n = min(numel(txBytes), numel(rxBytes));

    % ---- 逐字节差异 ----
    if n > 0
        diffMask = (double(txBytes(1:n)) ~= double(rxBytes(1:n)));
    else
        diffMask = false(0,1);
    end
    nerr    = sum(diffMask);
    lenOK   = (numel(txBytes) == numel(rxBytes));
    charOK  = isfield(metrics,'charOK') && logical(metrics.charOK);
    perfect = (nerr == 0) && lenOK && charOK;

    GREEN = [0.07 0.63 0.31];
    RED   = [0.85 0.25 0.25];
    BLUE  = [0.12 0.37 0.75];
    cMain = GREEN; if ~perfect, cMain = RED; end

    % ---- 文本解码 ----
    txTxt = native2unicode(txBytes.', 'UTF-8');
    rxTxt = native2unicode(rxBytes.', 'UTF-8');

    % ---- 组图 ----
    fig = figure('Position', [80 80 1000 460], 'Color', 'w', 'Visible', 'on');

    % ① 逐字节状态条
    ax1 = subplot(3,1,1); hold(ax1,'on');
    if n > 0
        idx = 1:n;
        if nerr == 0
            % ★ 注意: 画线用 plot(ax,...) —— line() 不接受 axes 句柄作为首参
            plot(ax1, [idx(1) idx(end)], [0.5 0.5], ...
                 'Color', [0.78 0.90 0.79], 'LineWidth', 8);
        else
            plot(ax1, [idx(1) idx(end)], [0.5 0.5], ...
                 'Color', [0.93 0.94 0.96], 'LineWidth', 8);
            bad = idx(diffMask);
            for k = 1:numel(bad)
                plot(ax1, [bad(k) bad(k)], [0.15 0.85], 'Color', RED, 'LineWidth', 1.4);
            end
        end
        xlim(ax1, [0.5, n+0.5]);
    end
    ylim(ax1, [0 1]); set(ax1, 'YTick', []);
    if nerr == 0
        tip = sprintf('逐字节状态：前 %d 字节全部正确', n);
        if ~lenOK, tip = [tip '  (差异仅在于长度)']; end
        tcol = GREEN;
    else
        tip = sprintf('逐字节状态：%d 个字节出错（红）', nerr);
        tcol = RED;
    end
    title(ax1, tip, 'FontSize', 11, 'Color', tcol, 'FontWeight', 'normal');
    xlabel(ax1, '字节序号', 'FontSize', 9);

    % ② 发送文本
    ax2 = subplot(3,1,2); axis(ax2, 'off');
    text(ax2, 0, 1, '发送', 'FontSize', 11, 'Color', BLUE, ...
         'FontWeight', 'bold', 'VerticalAlignment', 'top', 'Units', 'normalized');
    text(ax2, 0, 0.86, wrapText(txTxt, 46, 4), 'FontSize', 9, ...
         'VerticalAlignment', 'top', 'Units', 'normalized');

    % ③ 接收文本
    ax3 = subplot(3,1,3); axis(ax3, 'off');
    text(ax3, 0, 1, '接收', 'FontSize', 11, 'Color', cMain, ...
         'FontWeight', 'bold', 'VerticalAlignment', 'top', 'Units', 'normalized');
    text(ax3, 0, 0.86, wrapText(rxTxt, 46, 4), 'FontSize', 9, ...
         'VerticalAlignment', 'top', 'Units', 'normalized');

    % ---- 总标题(含结论) ----
    if lenOK
        concl = sprintf('字节正确率 %.4f%%', 100*(1 - nerr/max(numel(txBytes),1)));
        if perfect, concl = [concl '  ·  文本完全一致']; end
    else
        concl = sprintf('长度不符: 发送 %d B → 接收 %d B (多 %d B)', ...
                        numel(txBytes), numel(rxBytes), numel(rxBytes)-numel(txBytes));
    end
    sgtitle(sprintf('E4-TXT 文字端到端传输   [%s]   %s', link, concl), ...
            'FontSize', 12.5, 'Color', cMain);

    % ---- 保存 ----
    outdir = fullfile('plots', 'e4');
    if ~isfolder(outdir), mkdir(outdir); end
    fn = fullfile(outdir, sprintf('%s_text.png', link));
    try
        exportgraphics(fig, fn, 'Resolution', 130);
    catch
        saveas(fig, fn);
    end
    close(fig);
    fprintf('[OK] 文字对比图: %s\n', fn);
end

function s = wrapText(txt, per, maxLines)
%WRAPTEXT  按固定字符数折行 (便于在图中排版)
    txt = char(txt);
    lines = {};
    for i = 1:per:(per*maxLines)
        if i > numel(txt), break; end
        j = min(i+per-1, numel(txt));
        lines{end+1} = txt(i:j); %#ok<AGROW>
    end
    if numel(txt) > per*maxLines
        lines{end} = [lines{end} ' ...'];
    end
    s = strjoin(lines, newline);
end
