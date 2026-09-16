function tab_gallery(parent, projRoot)
%TAB_GALLERY  成果图册 Tab —— 自动扫描 plots/, 浏览全部实验成果图
%
%   左: 图片列表 (uilistbox)    右: 图预览 (uiaxes) + 说明 (uilabel)
%   回调在独立顶层文件: tg_refresh.m / tg_pick.m / tg_desc.m
%   显示用核心函数 imread + image (不依赖 Image Processing Toolbox)

    T = gui_theme();
    fig = ancestor(parent, 'figure');
    setappdata(fig, 'gallery_plotsDir', fullfile(projRoot, 'plots'));

    g = uigridlayout(parent, [2 1], 'RowHeight', {44, '1x'}, ...
                     'Padding', [14 14 14 14], 'RowSpacing', 8);

    %% --- 顶部标题条 ---
    gTop = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', 96}, 'Padding', [0 0 0 0]);
    uilabel(gTop, 'Text', '实验成果图册 — 自动扫描 plots/ 目录', ...
            'FontSize', T.fsTitle, 'FontWeight', 'bold', 'FontColor', T.head);
    uibutton(gTop, 'Text', '刷新列表', 'ButtonPushedFcn', @(~,~) tg_refresh(fig));

    %% --- 主体: 左列表 + 右预览 ---
    gMid = uigridlayout(g, [1 2], 'ColumnWidth', {250, '1x'}, ...
                        'Padding', [0 0 0 0], 'ColumnSpacing', 10);

    % 左: 列表
    pL = uipanel(gMid, 'Title', '图列表', 'FontSize', T.fsHead, ...
                 'BackgroundColor', T.card);
    glL = uigridlayout(pL, [1 1], 'Padding', [6 6 6 6]);
    lb = uilistbox(glL, 'Items', {'(扫描中...)'}, 'Value', '(扫描中...)', ...
                   'FontSize', T.fsBody, ...
                   'ValueChangedFcn', @(src, ~) tg_pick(fig, src.Value));
    setappdata(fig, 'gallery_list', lb);

    % 右: 预览 + 说明
    pR = uipanel(gMid, 'Title', '预览', 'FontSize', T.fsHead, ...
                 'BackgroundColor', T.card);
    glR = uigridlayout(pR, [2 1], 'RowHeight', {'1x', 70}, ...
                       'Padding', [8 8 8 8], 'RowSpacing', 6);
    ax = uiaxes(glR);
    ax.XTick = []; ax.YTick = [];
    setappdata(fig, 'gallery_ax', ax);
    lbl = uilabel(glR, 'Text', '从左侧列表选择一张图 ...', ...
                  'FontSize', T.fsBody, 'WordWrap', 'on', ...
                  'VerticalAlignment', 'top', 'FontColor', T.text);
    setappdata(fig, 'gallery_lbl', lbl);

    %% --- 初始化: 扫描列表 ---
    tg_refresh(fig);
end