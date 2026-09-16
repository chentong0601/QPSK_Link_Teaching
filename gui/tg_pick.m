function tg_pick(fig, fname)
%TG_PICK  成果图册 - 在右侧 axes 显示选中的图, 并填说明 (顶层函数)
    if isempty(fname), return; end
    if strncmp(fname, '--', 2), return; end
    if any(strcmp(fname, {'(无 plots/ 目录)', '(无图片)', '(扫描中...)'})), return; end

    plotsDir = getappdata(fig, 'gallery_plotsDir');
    ax  = getappdata(fig, 'gallery_ax');
    lbl = getappdata(fig, 'gallery_lbl');

    fp = fullfile(plotsDir, fname);
    if ~isfile(fp)
        lbl.Text = sprintf('文件不存在: %s', fp);
        return;
    end
    try
        I = imread(fp);
    catch ME
        lbl.Text = sprintf('读取失败: %s', ME.message);
        return;
    end

    cla(ax);
    image(ax, I);
    ax.XTick = []; ax.YTick = [];
    axis(ax, 'image');
    lbl.Text = tg_desc(fname);
end