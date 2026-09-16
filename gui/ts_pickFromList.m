function ts_pickFromList(fig, fn)
%TS_PICKFROMLIST  G1 数据体检 Tab - 下拉列表选项回调 (顶层函数)
    if strcmp(fn, '(无)'), return; end
    projRoot = getappdata(fig, 'sanity_projRoot');
    path = fullfile(projRoot, 'results', fn);
    setappdata(fig, 'sanity_currentFile', path);
    getappdata(fig, 'sanity_lblFile').Text = ['已选: ' fn];
    ts_analyze(fig, path);
end