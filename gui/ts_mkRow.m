function ts_mkRow(gl, labelText, appKey, fig)
%TS_MKROW  G1 数据体检 Tab - 建一行 "标签 + 数值" (顶层函数)
%   与原 mkRow 等价, 但独立文件以便 setappdata 解析无歧义
    uilabel(gl, 'Text', labelText, 'FontWeight', 'bold');
    lbl = uilabel(gl, 'Text', '-');
    setappdata(fig, appKey, lbl);
end