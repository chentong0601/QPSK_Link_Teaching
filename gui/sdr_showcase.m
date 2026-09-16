function sdr_showcase()
%SDR_SHOWCASE  实验3 通信收发机 —— 成果展示 GUI (主入口)
%
%   启动:
%     cd D:\ChenTong\SDR_project\QPSK_Link_Teaching
%     addpath('gui'); sdr_showcase
%
%   4 个 Tab:
%     1 实验总览 —— 18/18 实验清单 + 4 个亮点指标
%     2 成果图册 —— 自动扫描 plots/, 直接浏览全部成果图 ★
%     3 数据体检 —— 调用 rx_sanity_check.m 对任意 .mat 做三步体检
%     4 报告速览 —— 翻阅 博士课程-无线/*.md 实验报告
%
%   设计原则:
%     - 只**调用**现有 .m 函数, 不重写算法 (与 Simulink 展示层同源规则)
%     - 每个 UI 回调都是**独立顶层 .m 文件** (ts_*.m / tg_*.m / tr_*.m)
%       —— 不用嵌套子函数: R2024b 下嵌套函数对内建 GUI 函数解析有歧义
%     - 统一视觉: 配色 / 字号全部来自 gui_theme.m
%
%   需要 MATLAB R2020b+ (uigridlayout / uiaxes).

    %% ===== 路径 (基于本文件位置, 不依赖 pwd) =====
    thisDir  = fileparts(mfilename('fullpath'));
    projRoot = fileparts(thisDir);
    addpath(genpath(fullfile(projRoot, 'experiments')));
    addpath(fullfile(projRoot, 'config'));
    addpath(fullfile(projRoot, 'transmitter'));
    addpath(fullfile(projRoot, 'receiver'));
    addpath(fullfile(projRoot, 'sync'));
    addpath(fullfile(projRoot, 'video'));

    T = gui_theme();

    %% ===== 主窗口 (自适应屏幕 + 避开任务栏) =====
    scr = get(groot, 'ScreenSize');
    w = min(1320, floor(scr(3) - 60));
    h = min(800,  floor(scr(4) - 230));
    x = max(20, round((scr(3) - w) / 2));
    y = max(80, round(scr(4) - h - 120));

    fig = uifigure('Name', '实验3 通信收发机 — 成果展示', ...
                   'Position', [x y w h], 'Color', T.bg);

    %% ===== Tab group (交给 uigridlayout 承载, 不手动摆 Position) =====
    gMain = uigridlayout(fig, [1 1], 'Padding', [0 0 0 0], ...
                         'RowSpacing', 0, 'ColumnSpacing', 0);
    tg = uitabgroup(gMain);

    tab1 = uitab(tg, 'Title', '1  实验总览');
    tab2 = uitab(tg, 'Title', '2  成果图册 ★');
    tab3 = uitab(tg, 'Title', '3  数据体检');
    tab4 = uitab(tg, 'Title', '4  报告速览');

    tab_overview(tab1, projRoot);
    tab_gallery(tab2, projRoot);
    tab_sanity(tab3, projRoot);
    tab_reports(tab4, projRoot);

    tg.SelectedTab = tab2;      % ★ 默认停在"成果图册" —— 最有展示效果

    fprintf('\n[GUI] 实验3 成果展示 已启动  (%d x %d)\n', w, h);
    fprintf('  ① 实验总览   ② 成果图册 ★   ③ 数据体检   ④ 报告速览\n');
end