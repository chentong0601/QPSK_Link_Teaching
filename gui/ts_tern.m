function s = ts_tern(c, a, b)
%TS_TERN  G1 数据体检 Tab - 三元表达式 helper: c 真返 a, 否则返 b (顶层函数)
    if c, s = a; else, s = b; end
end