function e4_antsweep_compare(links)
%E4_ANTSWEEP_COMPARE  天线频率响应对比 —— 多链路叠加 (单张图)
%
%   读取 results/e4/antsweep/antsweep_<link>_*.mat (各链路最新一份),
%   叠加绘制"接收功率 vs 频率"与"EVM vs 频率"。
%   ★ 这是同类型同参数的图, 合并符合"高相关参数可排版对比"的原则。
%
%   用法: e4_antsweep_compare          % 默认 coax/short/long
%         e4_antsweep_compare({'short','long'})
%
%   输出: plots/e4/fig_antsweep_compare.png

    if nargin < 1 || isempty(links)
        links = {'short', 'long'};
    end
    lname = containers.Map({'coax','short','long','sim'}, ...
                           {'同轴线','短天线 5cm','长天线 10cm','仿真'});

    D = struct('link',{},'f',{},'pwr',{},'evm',{});
    for i = 1:numel(links)
        lk = links{i};
        fs = dir(fullfile('results','e4','antsweep', sprintf('antsweep_%s_*.mat', lk)));
        if isempty(fs), fprintf(2,'  [!] %s 无扫频数据\n', lk); continue; end
        [~, k] = max([fs.datenum]);
        M = load(fullfile(fs(k).folder, fs(k).name), 'metrics');
        m = M.metrics;
        D(end+1) = struct('link', lk, 'f', m.freq(:).', ...
                          'pwr', m.pwr(:).', 'evm', m.evm(:).'); %#ok<AGROW>
        fprintf('  已读 %-6s : %d 频点\n', lk, numel(m.freq));
    end
    if isempty(D), fprintf(2,'无数据\n'); return; end

    %% ---- 数值对比: 找各自最强/最弱频点 ----
    fprintf('\n');
    fprintf('====================================================================\n');
    fprintf('  天线频率响应对比\n');
    fprintf('====================================================================\n');
    fprintf('%-12s %14s %14s %16s\n', '链路', '最强频点', '最强功率', '2400MHz时功率');
    fprintf('%s\n', repmat('-',1,62));
    for i = 1:numel(D)
        [pm, ip] = max(D(i).pwr);
        f24 = interp1(D(i).f, D(i).pwr, 2.4e9, 'nearest');
        fprintf('%-12s %11.0f MHz %11.2f dBFS %13.2f dBFS\n', ...
                lname(D(i).link), D(i).f(ip)/1e6, pm, f24);
    end
    fprintf('%s\n', repmat('-',1,62));
    if numel(D) >= 2
        [~, i1] = max(D(1).pwr); [~, i2] = max(D(2).pwr);
        r = D(2).f(i2) / D(1).f(i1);
        fprintf('最优频点比: %s / %s = %.0f/%.0f MHz = %.2f 倍\n', ...
                lname(D(2).link), lname(D(1).link), ...
                D(2).f(i2)/1e6, D(1).f(i1)/1e6, r);
        % 逐频点差异
        fc = intersect(D(1).f, D(2).f);
        p1 = interp1(D(1).f, D(1).pwr, fc, 'nearest');
        p2 = interp1(D(2).f, D(2).pwr, fc, 'nearest');
        dd = p2 - p1;
        fprintf('逐频点功率差 (后-前): 均值 %+.1f dB, 范围 %+.1f ~ %+.1f dB\n', ...
                mean(dd), min(dd), max(dd));
        fprintf('  ⇒ 差异最大 %.1f dB (在 %.0f MHz), 说明两者频响结构显著不同\n', ...
                max(abs(dd)), fc(find(abs(dd)==max(abs(dd)),1))/1e6);
    end

    %% ---- 绘图 ----
    C = [0.07 0.63 0.31;   % 绿 short
         0.80 0.55 0.10;   % 橙 long
         0.12 0.37 0.75];  % 蓝 coax
    MK = {'s','^','o'};

    figure('Position',[70 70 900 660],'Color','w','Visible','on');
    ax1 = subplot(2,1,1); hold(ax1,'on');
    for i = 1:numel(D)
        c = C(mod(i-1,size(C,1))+1,:);
        plot(ax1, D(i).f/1e6, D(i).pwr, ['-' MK{mod(i-1,3)+1}], 'Color', c, ...
             'LineWidth',1.9,'MarkerSize',7,'MarkerFaceColor',c, ...
             'DisplayName', lname(D(i).link));
        [pm, ip] = max(D(i).pwr);
        plot(ax1, D(i).f(ip)/1e6, pm, 'p','Color',c,'MarkerSize',15, ...
             'MarkerFaceColor',c,'HandleVisibility','off');
    end
    % 参考线: 用 HandleVisibility 关闭, 避免混入图例 (曾出现 "data1" 图例项)
    yline(ax1, -25, '--', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
    text(ax1, max(D(1).f)/1e6, -24.3, '目标 −25 dBFS', ...
         'FontSize', 9, 'Color', [0.5 0.5 0.5], 'HorizontalAlignment', 'right');
    grid(ax1,'on'); set(ax1,'GridAlpha',0.22);
    ylabel(ax1,'接收功率 (dBFS)','FontSize',11);
    title(ax1,'天线频率响应对比 (★=各自最强频点)','FontSize',12);
    legend(ax1,'Location','southwest','FontSize',10);

    ax2 = subplot(2,1,2); hold(ax2,'on');
    for i = 1:numel(D)
        c = C(mod(i-1,size(C,1))+1,:);
        plot(ax2, D(i).f/1e6, D(i).evm, ['-' MK{mod(i-1,3)+1}], 'Color', c, ...
             'LineWidth',1.9,'MarkerSize',7,'MarkerFaceColor',c, ...
             'DisplayName', lname(D(i).link));
    end
    grid(ax2,'on'); set(ax2,'GridAlpha',0.22);
    xlabel(ax2,'频率 (MHz)','FontSize',11); ylabel(ax2,'RMS EVM (%)','FontSize',11);
    title(ax2,'EVM vs 频率','FontSize',12);
    legend(ax2,'Location','northwest','FontSize',10);

    outdir = fullfile('plots','e4');
    if ~isfolder(outdir), mkdir(outdir); end
    fn = fullfile(outdir,'fig_antsweep_compare.png');
    try, exportgraphics(gcf, fn, 'Resolution', 140); catch, saveas(gcf, fn); end
    fprintf('\n[OK] 频响对比图: %s\n', fn);
    fprintf('====================================================================\n\n');
end
