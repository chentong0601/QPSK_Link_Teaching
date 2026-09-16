function [rxBytes, stats] = e4_link(txBytes, params, rrc, scrambler, opt)
%E4_LINK  E4 统一链路入口 —— 按 opt.mode 分派到仿真或硬件实现
%
%   业务脚本只需设置 opt.mode, 无需关心底层是仿真信道还是真实硬件。
%
%     opt.mode = 'sim' (默认) → e4_sim_link   (AWGN + 频偏, 可扫 Eb/N0)
%              = 'hw'         → e4_hw_link    (Pluto 真实收发, 需在 GUI 运行)
%
%   用法:
%     opt.mode = 'hw'; opt.link = 'coax'; opt.rxGain = 30;
%     [rxBytes, stats] = e4_link(txBytes, params, rrc, scrambler, opt);
%
%   输出: 见 e4_sim_link / e4_hw_link (字段名一致, 便于统一落盘与分析)

    if nargin < 5 || isempty(opt), opt = struct(); end
    if ~isfield(opt, 'mode'), opt.mode = 'sim'; end

    if strcmpi(opt.mode, 'hw')
        [rxBytes, stats] = e4_hw_link(txBytes, params, rrc, scrambler, opt);
    else
        [rxBytes, stats] = e4_sim_link(txBytes, params, rrc, scrambler, opt);
        if ~isfield(stats, 'link'), stats.link = 'sim'; end
    end

    stats.mode = opt.mode;
end
