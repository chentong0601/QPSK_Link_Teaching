function [x, name] = ts_extractIQ(S)
%TS_EXTRACTIQ  从 load 出来的 struct 里抽 IQ 数组 (兼容多种存法) —— 顶层函数
%
%   与 ts_toComplex.m 配合: 本函数扫描字段名, 后者把任何存法还原成复列向量
    x = []; name = '';
    priority = {'xLong','rxData','x','iq','data','rxWave','rxSig','wave','rx'};
    excludes = {'psd','fAx','env','segPwr','clipFrac','edgeRatio','noiseFloor', ...
                'peakPower','bw3dB','occBW','occupancy','step','nSamples'};
    flds = fieldnames(S);
    order = [priority, setdiff(flds, [priority, excludes], 'stable')];
    for k = 1:numel(order)
        f = order{k};
        if ~isfield(S, f), continue; end
        v = ts_toComplex(S.(f));
        if ~isempty(v) && numel(v) > 1000
            x = v; name = f; return;
        end
    end
end