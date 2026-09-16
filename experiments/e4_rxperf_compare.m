function e4_rxperf_compare(links)
%E4_RXPERF_COMPARE  接收机 EVM 浴缸曲线 —— 多链路横向对比 (单张图)
%
%   读取 results/e4/rxperf/rxperf_<link>_*.mat (各链路最新一份),
%   把 EVM vs RxGain 曲线叠加绘制。这是【同类型、同参数】的图,
%   合并在一张内符合"同类型高相关参数可排版对比"的原则。
%
%   用法:
%     e4_rxperf_compare                 % 默认对比 coax / short / long
%     e4_rxperf_compare({'short','long'})
%
%   输出: plots/e4/fig_evm_bathtub_compare.png

    if nargin < 1 || isempty(links)
        links = {'coax', 'short', 'long'};
    end
    lname = containers.Map( ...
        {'coax','short','long','sim'}, ...
        {'同轴线', '短天线 5cm', '长天线 10cm', '仿真'});

    %% ---- 读取各链路最新数据 ----
    D = struct('link', {}, 'gain', {}, 'evm', {}, 'snr', {}, 'pwr', {}, 'dt', {});
    for i = 1:numel(links)
        lk = links{i};
        fs = dir(fullfile('results', 'e4', 'rxperf', sprintf('rxperf_%s_*.mat', lk)));
        if isempty(fs)
            fprintf(2, '  [!] 未找到 %s 的 rxperf 数据, 跳过\n', lk);
            continue;
        end
        [~, k] = max([fs.datenum]);
        M = load(fullfile(fs(k).folder, fs(k).name), 'metrics', 'cfg');
        m = M.metrics;
        D(end+1) = struct('link', lk, ...
                          'gain', m.gain(:).', 'evm', m.evm(:).', ...
                          'snr', m.snr(:).', 'pwr', m.pwr(:).', 'dt', m.dt(:).'); %#ok<AGROW>
        fprintf('  已读 %-6s : %d 档, 最优 RxGain=%g dB (EVM %.2f%%)\n', ...
                lk, numel(m.gain), m.gainBest, m.evmBest);
    end
    if isempty(D), fprintf(2, '无数据\n'); return; end

    %% ---- 打印汇总表 ----
    fprintf('\n');
    fprintf('====================================================================\n');
    fprintf('  接收机 EVM 浴缸曲线 —— 多链路对比\n');
    fprintf('====================================================================\n');
    fprintf('%-12s %14s %12s %14s %14s\n', '链路', '最优RxGain', '最优EVM', '0dB时功率', '50dB时功率');
    fprintf('%s\n', repmat('-', 1, 70));
    for i = 1:numel(D)
        g0  = D(i).pwr(1);
        g50 = D(i).pwr(end);
        [eb, ib] = min(D(i).evm);
        fprintf('%-12s %11g dB %10.2f%% %11.2f dBFS %11.2f dBFS\n', ...
                lname(D(i).link), D(i).gain(ib), eb, g0, g50);
    end
    fprintf('%s\n', repmat('-', 1, 70));
    % 链路损耗差 (用 0 dB 增益时的功率差衡量)
    if numel(D) >= 3
        d21 = D(2).pwr(1) - D(1).pwr(1);
        d32 = D(3).pwr(1) - D(2).pwr(1);
        fprintf('耦合差异: %s 比 %s 低 %.2f dB | %s 比 %s 低 %.2f dB\n', ...
                lname(D(2).link), lname(D(1).link), -d21, ...
                lname(D(3).link), lname(D(2).link), -d32);
    end

    %% ---- 绘图 (单张, 同为 EVM vs RxGain) ----
    C = [0.12 0.37 0.75;    % 蓝  coax
         0.07 0.63 0.31;    % 绿  short
         0.80 0.55 0.10];   % 橙  long
    MK = {'o', 's', '^'};

    figure('Position', [70 70 820 520], 'Color', 'w', 'Visible', 'on');
    ax = axes; hold(ax, 'on');
    for i = 1:numel(D)
        c = C(mod(i-1, size(C,1)) + 1, :);
        plot(ax, D(i).gain, D(i).evm, ['-' MK{mod(i-1,3)+1}], ...
             'Color', c, 'LineWidth', 1.9, 'MarkerSize', 7, ...
             'MarkerFaceColor', c, 'DisplayName', lname(D(i).link));
        % 标注各链路最低点
        [eb, ib] = min(D(i).evm);
        plot(ax, D(i).gain(ib), eb, 'p', 'Color', c, 'MarkerSize', 14, ...
             'MarkerFaceColor', c, 'HandleVisibility', 'off');
    end
    grid(ax, 'on'); set(ax, 'GridAlpha', 0.22);
    xlabel(ax, 'RxGain (dB)', 'FontSize', 12);
    ylabel(ax, 'RMS EVM (%)', 'FontSize', 12);
    title(ax, '接收机 EVM vs 接收增益 —— 三种连接方式对比', 'FontSize', 13);
    legend(ax, 'Location', 'north', 'FontSize', 10);
    text(ax, 0.02, 0.96, '★ = 各链路 EVM 最低点', 'Units', 'normalized', ...
         'FontSize', 9, 'Color', [0.4 0.4 0.4], 'VerticalAlignment', 'top');

    outdir = fullfile('plots', 'e4');
    if ~isfolder(outdir), mkdir(outdir); end
    fn = fullfile(outdir, 'fig_evm_bathtub_compare.png');
    try
        exportgraphics(gcf, fn, 'Resolution', 140);
    catch
        saveas(gcf, fn);
    end
    fprintf('[OK] 对比图: %s\n', fn);
    fprintf('====================================================================\n\n');
end
