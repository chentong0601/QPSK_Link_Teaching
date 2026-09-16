function tg_refresh(fig)
%TG_REFRESH  成果图册 - 重新扫描 plots/ 并刷新左侧列表 (顶层函数)
    plotsDir = getappdata(fig, 'gallery_plotsDir');
    lb = getappdata(fig, 'gallery_list');

    if ~isfolder(plotsDir)
        lb.Items = {'(无 plots/ 目录)'};
        lb.Value = '(无 plots/ 目录)';
        return;
    end
    d = dir(fullfile(plotsDir, '*.png'));
    if isempty(d)
        lb.Items = {'(无图片)'};
        lb.Value = '(无图片)';
        return;
    end
    names = sort({d.name});
    % 首项保留占位, 维持"未选"态 (与 tab_sanity 下拉框同一处理)
    lb.Items = [{'-- 请选择一张图 --'}, names];
    lb.Value = '-- 请选择一张图 --';
end