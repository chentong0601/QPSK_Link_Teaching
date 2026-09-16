function tr_refresh(fig)
%TR_REFRESH  报告速览 - 扫描报告目录, 刷新左侧列表 (顶层函数)
    repDir = getappdata(fig, 'reports_dir');
    lb = getappdata(fig, 'reports_list');

    if ~isfolder(repDir)
        lb.Items = {'(无报告目录)'};
        lb.Value = '(无报告目录)';
        return;
    end
    d = dir(fullfile(repDir, '*.md'));
    if isempty(d)
        lb.Items = {'(无报告)'};
        lb.Value = '(无报告)';
        return;
    end
    names = sort({d.name});
    lb.Items = [{'-- 请选择一份报告 --'}, names];
    lb.Value = '-- 请选择一份报告 --';
end