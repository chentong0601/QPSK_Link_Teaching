function ts_pickFile(fig)
%TS_PICKFILE  G1 数据体检 Tab - "选择文件..." 按钮回调 (顶层函数)
%   从原 tab_sanity 嵌套子函数拆出; 拆出原因见 tab_sanity.m 头部
    projRoot = getappdata(fig, 'sanity_projRoot');
    [fn, fp] = uigetfile(fullfile(projRoot, 'results', '*.mat'), ...
                        '选择 IQ 数据 .mat 文件');
    if isequal(fn, 0), return; end
    path = fullfile(fp, fn);
    setappdata(fig, 'sanity_currentFile', path);
    getappdata(fig, 'sanity_lblFile').Text = ['已选: ' fn];
    ts_analyze(fig, path);
end