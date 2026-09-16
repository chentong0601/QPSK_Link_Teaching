function v = ts_toComplex(v)
%TS_TOCOMPLEX  把各种存法统一成复列向量 —— 顶层函数
%
%   cell → 递归取首个
%   struct(real, imag) → 复数 (v7.3 / HDF5 复合类型存法)
%   其它非数值 → [] (放弃)
    while iscell(v)
        if isempty(v), v = []; return; end
        v = v{1};
    end
    if isstruct(v)
        if isfield(v, 'real') && isfield(v, 'imag')
            try
                re = [v(:).real];  re = re(:);
                im = [v(:).imag];  im = im(:);
            catch
                v = []; return;
            end
            if isempty(re) || numel(re) ~= numel(im), v = []; return; end
            v = double(re) + 1i*double(im);
        else
            v = []; return;
        end
    end
    if ~isnumeric(v) && ~islogical(v), v = []; return; end
    v = v(:);
end