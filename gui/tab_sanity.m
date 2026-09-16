function tab_sanity(parent, projRoot)
%TAB_SANITY  G1 数据体检 Tab —— 主函数(无嵌套函数, 全部回调拆到独立 .m)
%
%   ★ 拆分原因 (2026-09-13):
%     原 tab_sanity.m 把所有回调作为嵌套子函数, 但 R2024b 在嵌套函数
%     作用域下, 对"主函数体没用过"的函数名(本例 getappdata)解析有歧义,
%     会把它误判为变量, 运行时找不到 → 报"无法识别"。
%     checkcode 已预警 L 91/103/174 "可能在定义变量前使用了变量"。
%     拆成独立 .m 后, 每个回调是顶层函数, 解析无歧义。
%
%   关联文件 (gui/ 下):
%     ts_pickFile.m  ts_pickFromList.m  ts_refreshList.m  ts_reAnalyze.m
%     ts_analyze.m   ts_extractIQ.m     ts_toComplex.m
%     ts_exportReport.m  ts_mkRow.m  ts_tern.m
%
%   状态存储: setappdata/getappdata 挂到 figure 上
%            (matlab.ui.container.Tab 没有 UserData 属性)

    fig = ancestor(parent, 'figure');
    setappdata(fig, 'sanity_projRoot', projRoot);

    %% ===== 布局: 上 / 中 / 下 =====
    g = uigridlayout(parent, [3 1], ...
                     'RowHeight', {54, '1x', 56}, ...
                     'Padding', [10 10 10 10]);

    %% ===== 顶部: 文件选择条 =====
    pTop = uipanel(g, 'Title', '1. 选择 .mat 数据文件 (results/ 下)', 'FontSize', 11);
    glTop = uigridlayout(pTop, [1 4], 'ColumnWidth', {130, '1x', 100, 180}, ...
                         'Padding', [8 6 8 6]);
    uibutton(glTop, 'Text', '选择文件...', ...
             'ButtonPushedFcn', @(~,~) ts_pickFile(fig));
    lblFile = uilabel(glTop, 'Text', '(未选择)', ...
                     'FontColor', [0.5 0.5 0.5]);
    uibutton(glTop, 'Text', '刷新列表', ...
             'ButtonPushedFcn', @(~,~) ts_refreshList(fig));
    ddList = uidropdown(glTop, 'Items', {'(无)'}, 'Value', '(无)', ...
                        'ValueChangedFcn', @(src,~) ts_pickFromList(fig, src.Value));
    setappdata(fig, 'sanity_lblFile', lblFile);
    setappdata(fig, 'sanity_ddList',  ddList);

    %% ===== 中部: 左(诊断结果) + 右(4 子图) =====
    pMid = uipanel(g, 'Title', '2. 三步体检: 完整性 → 硬边界 → 分布形态', 'FontSize', 11);
    glMid = uigridlayout(pMid, [1 2], 'ColumnWidth', {300, '1x'});

    % ---- 左: 诊断结果 ----
    pRes = uipanel(glMid, 'Title', '诊断结果');
    glRes = uigridlayout(pRes, [6 2], ...
                         'RowHeight', {24, 24, 24, 24, 24, '1x'}, ...
                         'ColumnWidth', {110, '1x'});
    ts_mkRow(glRes, '样本数:',      'sanity_lblN', fig);
    ts_mkRow(glRes, '唯一量化级:',  'sanity_lblU', fig);
    ts_mkRow(glRes, '精确零样本:',  'sanity_lblZ', fig);
    ts_mkRow(glRes, '峰值幅度:',    'sanity_lblP', fig);
    ts_mkRow(glRes, '边缘堆积比:',  'sanity_lblE', fig);
    uilabel(glRes, 'Text', '结论:', 'FontWeight', 'bold');
    pVerdict = uipanel(glRes, 'BackgroundColor', [0.95 0.95 0.95]);
    glV = uigridlayout(pVerdict, [1 1], 'Padding', [8 8 8 8]);
    lblV = uilabel(glV, 'Text', '(选择文件后显示)', ...
                   'WordWrap', 'on', 'VerticalAlignment', 'top', 'FontSize', 11);
    setappdata(fig, 'sanity_lblV', lblV);

    % ---- 右: 4 子图 axes ----
    pFig = uipanel(glMid, 'Title', '诊断图 (I直方图 / IQ散点 / 幅度直方图 / 功率包络)');
    glFig = uigridlayout(pFig, [2 2], 'Padding', [8 8 8 8]);
    % ★ 初始隐藏坐标系: 否则空图会显示 0~1 刻度, 看起来"比例异常";
    %   选文件后由 ts_analyze 里的 axis(ax,'on') 打开
    ax1 = uiaxes(glFig); title(ax1, 'I 直方图');   axis(ax1, 'off');
    ax2 = uiaxes(glFig); title(ax2, 'IQ 散点');    axis(ax2, 'off');
    ax3 = uiaxes(glFig); title(ax3, '幅度直方图'); axis(ax3, 'off');
    ax4 = uiaxes(glFig); title(ax4, '功率包络');   axis(ax4, 'off');
    setappdata(fig, 'sanity_ax', [ax1, ax2, ax3, ax4]);

    %% ===== 底部: 操作按钮 =====
    pBot = uipanel(g, 'Title', '3. 操作');
    glBot = uigridlayout(pBot, [1 4], ...
                         'ColumnWidth', {120, 140, 140, '1x'}, 'Padding', [8 6 8 6]);
    uibutton(glBot, 'Text', '重新分析', ...
             'ButtonPushedFcn', @(~,~) ts_reAnalyze(fig));
    uibutton(glBot, 'Text', '导出诊断 .md', ...
             'ButtonPushedFcn', @(~,~) ts_exportReport(fig));
    uibutton(glBot, 'Text', '打开结果目录', ...
             'ButtonPushedFcn', @(~,~) winopen(fullfile(projRoot, 'results')));
    uilabel(glBot, 'Text', '★ 全部离线分析; 不上传不外发', ...
            'FontColor', [0.5 0.5 0.5], 'HorizontalAlignment', 'right');

    %% ===== 初始化: 填列表 =====
    ts_refreshList(fig);
end