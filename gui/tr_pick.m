function tr_pick(fig, fname)
%TR_PICK  报告速览 - 读取并显示 .md 正文 (顶层函数)
    if isempty(fname), return; end
    if strncmp(fname, '--', 2), return; end
    if any(strcmp(fname, {'(无报告目录)', '(无报告)', '(扫描中...)'})), return; end

    repDir = getappdata(fig, 'reports_dir');
    ta = getappdata(fig, 'reports_text');
    fp = fullfile(repDir, fname);
    if ~isfile(fp)
        ta.Value = {sprintf('文件不存在: %s', fp)};
        return;
    end
    try
        txt = fileread(fp);
    catch ME
        ta.Value = {sprintf('读取失败: %s', ME.message)};
        return;
    end
    lines = splitlines(txt);
    if numel(lines) > 3000
        lines = [lines(1:3000); {'... (内容过长, 已截断)'}];
    end
    ta.Value = lines;
end