function tab_reports(parent, projRoot)
%TAB_REPORTS  报告速览 Tab —— 直接在 GUI 里翻阅实验报告 .md
%
%   左: 报告列表 (uilistbox)   右: 正文 (uitextarea, 只读)
%   回调在独立顶层文件: tr_refresh.m / tr_pick.m

    T = gui_theme();
    fig = ancestor(parent, 'figure');
    setappdata(fig, 'reports_dir', fullfile(projRoot, '博士课程-无线'));

    g = uigridlayout(parent, [2 1], 'RowHeight', {44, '1x'}, ...
                     'Padding', [14 14 14 14], 'RowSpacing', 8);

    %% --- 顶部标题条 ---
    gTop = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', 96}, 'Padding', [0 0 0 0]);
    uilabel(gTop, 'Text', '实验报告速览 — 博士课程-无线/ 下的 Markdown 报告', ...
            'FontSize', T.fsTitle, 'FontWeight', 'bold', 'FontColor', T.head);
    uibutton(gTop, 'Text', '刷新列表', 'ButtonPushedFcn', @(~,~) tr_refresh(fig));

    %% --- 主体: 左列表 + 右正文 ---
    gMid = uigridlayout(g, [1 2], 'ColumnWidth', {290, '1x'}, ...
                        'Padding', [0 0 0 0], 'ColumnSpacing', 10);

    pL = uipanel(gMid, 'Title', '报告列表', 'FontSize', T.fsHead, ...
                 'BackgroundColor', T.card);
    glL = uigridlayout(pL, [1 1], 'Padding', [6 6 6 6]);
    lb = uilistbox(glL, 'Items', {'(扫描中...)'}, 'Value', '(扫描中...)', ...
                   'FontSize', T.fsBody, ...
                   'ValueChangedFcn', @(src, ~) tr_pick(fig, src.Value));
    setappdata(fig, 'reports_list', lb);

    pR = uipanel(gMid, 'Title', '正文 (只读)', 'FontSize', T.fsHead, ...
                 'BackgroundColor', T.card);
    glR = uigridlayout(pR, [1 1], 'Padding', [6 6 6 6]);
    ta = uitextarea(glR, 'Editable', 'off', 'FontSize', T.fsBody, ...
                    'Value', {'从左侧选择一份报告 ...'});
    setappdata(fig, 'reports_text', ta);

    %% --- 初始化: 扫描列表 ---
    tr_refresh(fig);
end