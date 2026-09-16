function e4_plot_constellation(links)
%E4_PLOT_CONSTELLATION  接收星座图 —— 多链路对比 (单张图)
%
%   从 rxperf 存档的 IQ 中解调出符号, 经逐块复增益均衡后绘制星座图。
%   星座图是接收机信号质量的直观可视化, 也是论文中最常用的图之一。
%
%   用法:
%     e4_plot_constellation                 % 对比 coax / short / long
%     e4_plot_constellation({'short'})
%
%   输出: plots/e4/fig_constellation_<link>.png (单链路)
%         plots/e4/fig_constellation_compare.png (多链路, 同类型可合并)

    if nargin < 1 || isempty(links)
        links = {'coax', 'short', 'long'};
    end
    lname = containers.Map({'coax','short','long','sim'}, ...
                           {'同轴线','短天线 5cm','长天线 10cm','仿真'});

    thisDir = fileparts(mfilename('fullpath'));
    cd(fileparts(thisDir));
    addpath('config'); addpath('transmitter'); addpath('receiver');
    addpath('sync'); addpath('experiments');

    params = init_params;
    L  = params.SamplesPerSym;
    rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
    [preBits, ~, preSym] = gen_frame_sequences(params);
    preSym = preSym(:);
    nSymBlk = numel(preSym);
    guardLen = 80;
    [w0, ~] = tx_baseband(preSym, L, rrc);
    blkStep = numel(w0) + guardLen;
    nPre    = 12;

    Rec = struct('link', {}, 'sym', {}, 'evm', {}, 'snr', {}, 'gain', {});
    for i = 1:numel(links)
        lk = links{i};
        fs = dir(fullfile('results','e4','rxperf', sprintf('rxperf_%s_*.mat', lk)));
        if isempty(fs), fprintf(2,'  [!] %s 无数据\n', lk); continue; end
        [~, k] = max([fs.datenum]);
        M = load(fullfile(fs(k).folder, fs(k).name), 'metrics', 'raw');
        m = M.metrics; r = M.raw;

        % 取存档 IQ 中 EVM 最小的那一档 (即该链路最佳工作点)
        if ~isfield(r,'iqGains') || isempty(r.iqGains)
            fprintf(2,'  [!] %s 无 IQ 存档\n', lk); continue;
        end
        gs = r.iqGains(:).';
        ev = interp1(m.gain, m.evm, gs, 'nearest');
        [~, ig] = min(ev);
        iq = r.iqVals{ig}(:);

        % 用与 rx_quality 相同的逻辑提取并均衡符号
        [symEq, evm0] = extract_syms(iq, preSym, L, rrc, nSymBlk, nPre, blkStep);
        if isempty(symEq), fprintf(2,'  [!] %s 符号提取失败\n', lk); continue; end
        Rec(end+1) = struct('link', lk, 'sym', symEq, 'evm', evm0, ...
                            'snr', 20*log10(100/max(evm0,eps)), 'gain', gs(ig)); %#ok<AGROW>
        fprintf('  %-6s : 取 RxGain=%g dB 档, %d 符号, EVM %.2f%%\n', ...
                lk, gs(ig), numel(symEq), evm0);
    end
    if isempty(Rec), fprintf(2,'无可用数据\n'); return; end

    %% ---- 绘图 ----
    C = [0.12 0.37 0.75; 0.07 0.63 0.31; 0.80 0.55 0.10];
    outdir = fullfile('plots','e4');
    if ~isfolder(outdir), mkdir(outdir); end

    if numel(Rec) == 1
        % 单链路: 独立成图, 含理想点标记
        plot_one(Rec(1), C(1,:), lname(Rec(1).link), ...
                 fullfile(outdir, sprintf('fig_constellation_%s.png', Rec(1).link)));
    else
        % 多链路: 单张, 子图并排 (同类型同参数, 符合合并原则)
        n = numel(Rec);
        figure('Position', [60 60 380*n 420], 'Color', 'w', 'Visible', 'on');
        for i = 1:n
            ax = subplot(1, n, i);
            draw_ax(ax, Rec(i), C(mod(i-1,3)+1,:));
            title(ax, sprintf('%s\nEVM %.2f%%  (RxGain %g dB)', ...
                  lname(Rec(i).link), Rec(i).evm, Rec(i).gain), 'FontSize', 11);
        end
        sgtitle('接收星座图对比 (均衡后, 同一符号对齐)', 'FontSize', 13);
        fn = fullfile(outdir, 'fig_constellation_compare.png');
        try, exportgraphics(gcf, fn, 'Resolution', 140); catch, saveas(gcf, fn); end
        fprintf('[OK] 星座图对比: %s\n', fn);
    end
end


function [symEq, evm] = extract_syms(iq, preSym, L, rrc, nSymBlk, nPre, blkStep)
%EXTRACT_SYMS  从 IQ 提取并按块均衡的符号 (与 rx_quality 同逻辑)
    symEq = []; evm = NaN;
    d  = floor(numel(rrc)/2);
    mf = conv(iq(:), rrc);
    mf = mf(d+1 : d+numel(iq));

    span = blkStep;
    if span > numel(mf) - blkStep, span = max(1, numel(mf) - blkStep); end
    bestE = Inf; bestS = [];
    for off = 1:span
        idxAll = zeros(nSymBlk*nPre, 1); nb = 0;
        for k = 0:(nPre-1)
            base = off + k*blkStep;
            ii = base + (0:(nSymBlk-1))*L;
            idxAll(nb+1:nb+nSymBlk) = ii(:); nb = nb + nSymBlk;
        end
        if any(idxAll < 1) || any(idxAll > numel(mf)), continue; end
        Rs = reshape(mf(round(idxAll)), nSymBlk, nPre);
        idealM = repmat(preSym, 1, nPre);
        alpha = sum(conj(idealM).*Rs,1) ./ sum(abs(idealM).^2,1);
        if any(abs(alpha) < 1e-9), continue; end
        RsEq = Rs ./ repmat(alpha, nSymBlk, 1);
        err = RsEq - idealM;
        e = sqrt(mean(abs(err(:)).^2)/mean(abs(idealM(:)).^2))*100;
        if e < bestE, bestE = e; bestS = RsEq(:); end
    end
    if isempty(bestS), return; end
    symEq = bestS; evm = bestE;
end


function draw_ax(ax, R, c)
%DRAW_AX  在给定 axes 上绘制星座图
    hold(ax, 'on');
    th = linspace(0, 2*pi, 200);
    % 参考: 理想 QPSK 点 (归一化单位功率)
    ip = (1/sqrt(2)) * [1+1j; -1+1j; -1-1j; 1-1j];
    % EVM 半径参考圆 (以理想点为中心)
    r = R.evm/100;
    for k = 1:4
        plot(ax, real(ip(k)) + r*cos(th), imag(ip(k)) + r*sin(th), ':', ...
             'Color', [0.75 0.75 0.75], 'LineWidth', 0.8);
    end
    plot(ax, real(ip), imag(ip), 'k+', 'MarkerSize', 10, 'LineWidth', 1.4);
    plot(ax, real(R.sym), imag(R.sym), '.', 'Color', c, 'MarkerSize', 8);
    axis(ax, 'equal'); grid(ax, 'on'); set(ax, 'GridAlpha', 0.2);
    xlim(ax, [-1.8 1.8]); ylim(ax, [-1.8 1.8]);
    xlabel(ax, 'I', 'FontSize', 10); ylabel(ax, 'Q', 'FontSize', 10); hold(ax, 'off');
end


function plot_one(R, c, nm, fn)
%PLOT_ONE  单链路星座图 (独立文件)
    figure('Position', [80 80 560 540], 'Color', 'w', 'Visible', 'on');
    ax = axes; draw_ax(ax, R, c);
    title(ax, sprintf('接收星座图 —— %s\nEVM %.2f%%  SNR %.2f dB  (RxGain %g dB)', ...
          nm, R.evm, R.snr, R.gain), 'FontSize', 12);
    legend(ax, {'EVM 参考圆','理想点','接收点'}, 'Location', 'northeastoutside', 'FontSize', 9);
    try, exportgraphics(gcf, fn, 'Resolution', 140); catch, saveas(gcf, fn); end
    fprintf('[OK] 星座图: %s\n', fn);
end
