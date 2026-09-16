function ts_analyze(fig, matPath)
%TS_ANALYZE  G1 数据体检 Tab - 核心: 加载 → 找 IQ → 找 fs → 调体检 → 填面板
%   顶层函数, 状态全部从 fig 的 appdata 读取, 不依赖任何共享工作区
    fprintf('\n[GUI] 加载 %s\n', matPath);

    try
        S = load(matPath);
    catch ME
        uialert(fig, sprintf('加载失败: %s', ME.message), '读取错误');
        return;
    end

    % --- 找 IQ ---
    [x, xName] = ts_extractIQ(S);
    if isempty(x)
        uialert(fig, sprintf('在 %s 中找不到 IQ 数组', matPath), '未找到 IQ');
        return;
    end

    % --- 找 fs ---
    fs = 1;
    fsKeys = {'SampleRate', 'fs', 'Fs', 'sampleRate', 'BasebandSampleRate'};
    for k = 1:numel(fsKeys)
        if isfield(S, 'CFG') && isfield(S.CFG, fsKeys{k})
            fs = S.CFG.(fsKeys{k}); break;
        end
        if isfield(S, fsKeys{k}) && isnumeric(S.(fsKeys{k}))
            fs = S.(fsKeys{k}); break;
        end
    end
    if ~isscalar(fs) || ~isnumeric(fs) || fs <= 0, fs = 1; end

    % --- 限长 (避免绘图卡死) ---
    if numel(x) > 1e6
        x = x(1:1e6);
    end

    fprintf('[GUI] IQ 字段: %s (N=%d), fs=%.3f MHz\n', xName, numel(x), fs/1e6);

    % --- 调体检 (画到 GUI 的 axes 上) ---
    [~, tag] = fileparts(matPath);
    ax = getappdata(fig, 'sanity_ax');
    for k = 1:numel(ax)
        axis(ax(k), 'on');      % ★ 初始为 off, 绘图前恢复坐标系
    end
    report = rx_sanity_check(x, fs, tag, ax);

    % --- 填左列 ---
    getappdata(fig, 'sanity_lblN').Text = sprintf('%d (%.2f s @ %.2f MHz)', ...
        report.nSamples, report.nSamples/fs, fs/1e6);
    getappdata(fig, 'sanity_lblU').Text = sprintf('%d 级, 步长 %.6f', ...
        report.nUniqueI, report.step);
    getappdata(fig, 'sanity_lblZ').Text = sprintf('%d (%.4f%%)', ...
        report.nExactZero, report.nExactZero/report.nSamples*100);
    getappdata(fig, 'sanity_lblP').Text = sprintf('%.4f %s', ...
        report.envMax, ts_tern(report.atFullScale, '[满量程]', '[未满]'));
    getappdata(fig, 'sanity_lblE').Text = sprintf('%.2f (触顶 %.3f%%)', ...
        report.edgeRatio, report.clipFrac*100);

    lblV = getappdata(fig, 'sanity_lblV');
    lblV.Text = report.verdict;
    if report.isClipped
        lblV.FontColor = [0.85 0.10 0.10];     % 红: ADC 饱和
    elseif report.nExactZero > 0.001 * report.nSamples
        lblV.FontColor = [0.90 0.50 0.05];     % 橙: 采集可疑
    else
        lblV.FontColor = [0.10 0.50 0.10];     % 绿: 健康
    end

    setappdata(fig, 'sanity_lastReport', report);
    setappdata(fig, 'sanity_lastFs',     fs);
    setappdata(fig, 'sanity_lastIQName', xName);
end