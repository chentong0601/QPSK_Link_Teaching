function ts_refreshList(fig)
%TS_REFRESHLIST  G1 数据体检 Tab - 刷新结果文件下拉框 (顶层函数)
    projRoot = getappdata(fig, 'sanity_projRoot');
    dd = getappdata(fig, 'sanity_ddList');
    resDir = fullfile(projRoot, 'results');
    if ~isfolder(resDir)
        dd.Items = {'(无 results/ 目录)'};
        dd.Value = '(无 results/ 目录)';
        return;
    end
    files = dir(fullfile(resDir, '*.mat'));
    if isempty(files)
        dd.Items = {'(空目录)'};
        dd.Value = '(空目录)';
    else
        [~, idx] = sort([files.datenum], 'descend');
        files = files(idx);
        % 保留 '(无)' 项: 否则设置 Items 后 Value 会自动跳到第一个文件名,
        % 与左侧 "(未选择)" 标签不一致, 且无法回到"未选"态
        dd.Items = [{'(无)'}, {files.name}];
        dd.Value = '(无)';
    end
end