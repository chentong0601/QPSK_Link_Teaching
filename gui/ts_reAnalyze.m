function ts_reAnalyze(fig)
%TS_REANALYZE  G1 数据体检 Tab - "重新分析" 按钮回调 (顶层函数)
    if isappdata(fig, 'sanity_currentFile')
        ts_analyze(fig, getappdata(fig, 'sanity_currentFile'));
    end
end