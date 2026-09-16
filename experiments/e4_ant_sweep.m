function e4_ant_sweep(link, varargin)
%E4_ANT_SWEEP  天线/链路 频率响应扫描 —— 回答"不同天线的适用频段是否不同"
%
%   在每个频点发射同一前导波形, 记录接收功率与 EVM, 得到
%   【功率 vs 频率】与【EVM vs 频率】两条曲线。
%   天线是窄带/宽带器件, 其频响曲线的平坦度直接反映"适用频段"。
%
%   用法 (MATLAB GUI 或 -batch 均可):
%     e4_ant_sweep('long')                       % 扫默认频点
%     e4_ant_sweep('short', 'freqs', 400e6:400e6:3600e6)
%     e4_ant_sweep('long', 'rxGain', 30, 'txGain', -20)
%
%   产物:
%     results/e4/antsweep/antsweep_<link>_<ts>.mat
%     plots/e4/fig_antsweep_<link>.png
%
%   注意: 扫描范围受 Pluto 硬件限制 (325 MHz ~ 3.8 GHz);
%         超出范围的频点会被自动裁剪。

    if nargin < 1 || isempty(link), link = 'long'; end
    opt.freqs  = 400e6:200e6:3600e6;    % 默认扫 17 个频点
    opt.rxGain = 30;
    opt.txGain = -20;
    opt.nRep   = 2;
    for i = 1:2:numel(varargin)
        if i+1 <= numel(varargin), opt.(varargin{i}) = varargin{i+1}; end
    end

    thisDir = fileparts(mfilename('fullpath'));
    cd(fileparts(thisDir));
    addpath('config'); addpath('transmitter'); addpath('receiver');
    addpath('sync'); addpath('experiments');

    params = init_params;
    L   = params.SamplesPerSym;
    rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
    [preBits, ~, preSym] = gen_frame_sequences(params);

    guardLen = 80;
    [w0, ~]  = tx_baseband(preSym(:), L, rrc);
    blkStep  = numel(w0) + guardLen;
    blkWave  = [];
    for k = 1:10
        blkWave = [blkWave; w0*0.9/max(abs(w0)); zeros(guardLen,1)]; %#ok<AGROW>
    end

    % Pluto 硬件范围 (ADALM-Pluto 出厂 325 MHz ~ 3.8 GHz)
    fmin = 325e6; fmax = 3.8e9;
    fr = opt.freqs(opt.freqs >= fmin & opt.freqs <= fmax);
    if numel(fr) < numel(opt.freqs)
        fprintf('  (已裁剪 %d 个超出 Pluto 范围的频点)\n', numel(opt.freqs)-numel(fr));
    end

    fprintf('\n');
    fprintf('################################################################\n');
    fprintf('#   频率响应扫描 —— link = %s\n', link);
    fprintf('################################################################\n');
    fprintf('  频点数 %d (%.0f ~ %.0f MHz), RxGain=%d dB, TxGain=%d dB\n', ...
            numel(fr), min(fr)/1e6, max(fr)/1e6, opt.rxGain, opt.txGain);
    fprintf('  单块波形 %d 采样, 块周期 %d\n\n', numel(w0), blkStep);

    try
        r = findPlutoRadio();
        if isempty(r), fprintf(2,'[!] 未发现 Pluto\n'); return; end
    catch
        fprintf(2,'[!] 无法检测 Pluto\n'); return;
    end

    nF = numel(fr);
    pwr = nan(1,nF); evmv = nan(1,nF); snrv = nan(1,nF);
    for i = 1:nF
        f = fr(i);
        fprintf('--- %6.0f MHz ---\n', f/1e6);
        p2 = params; p2.CenterFrequency = f;
        o  = struct('txGain', opt.txGain, 'rxGain', opt.rxGain, ...
                    'nRep', opt.nRep, 'verbose', false);
        try
            [iq, st] = e4_hw_rawtxrx(blkWave, p2, o);
            pwr(i) = st.rxPowerDbfs;
            [ev, ~, ~, ~, ~] = rx_quality_light(iq, preSym, L, rrc, 10, blkStep);
            evmv(i) = ev;
            snrv(i) = 20*log10(100/max(ev,eps));
            fprintf('  功率 %7.2f dBFS | EVM %6.2f %% | SNR %5.2f dB\n', ...
                    pwr(i), evmv(i), snrv(i));
        catch ME
            fprintf(2,'  失败: %s\n', ME.message);
        end
    end

    %% ---- 落盘 ----
    outdir = fullfile('results','e4','antsweep');
    if ~isfolder(outdir), mkdir(outdir); end
    ts = datestr(now,'yyyymmdd_HHMMSS');
    cfg = struct('link',link,'txGain',opt.txGain,'rxGain',opt.rxGain, ...
                 'nRep',opt.nRep,'timestamp',datestr(now,'yyyy-mm-dd HH:MM:SS'));
    metrics = struct('freq',fr,'pwr',pwr,'evm',evmv,'snr',snrv);
    fn = fullfile(outdir, sprintf('antsweep_%s_%s.mat', link, ts));
    save(fn,'cfg','metrics','-v7.3');
    fprintf('\n[OK] 数据已存 %s\n', fn);

    %% ---- 出图 (单张: 功率与EVM 双子图, 同为"vs 频率"故可合并) ----
    figure('Position',[70 70 900 640],'Color','w','Visible','on');
    ax1 = subplot(2,1,1);
    plot(ax1, fr/1e6, pwr, '-o', 'LineWidth',1.8, 'MarkerSize',6, ...
         'MarkerFaceColor','auto');
    grid(ax1,'on'); set(ax1,'GridAlpha',0.22);
    ylabel(ax1,'接收功率 (dBFS)','FontSize',11);
    title(ax1, sprintf('频率响应 —— %s', link), 'FontSize', 12);
    ax2 = subplot(2,1,2);
    plot(ax2, fr/1e6, evmv, '-s', 'LineWidth',1.8, 'MarkerSize',6, ...
         'MarkerFaceColor','auto');
    grid(ax2,'on'); set(ax2,'GridAlpha',0.22);
    xlabel(ax2,'频率 (MHz)','FontSize',11); ylabel(ax2,'RMS EVM (%)','FontSize',11);

    outdir2 = fullfile('plots','e4');
    if ~isfolder(outdir2), mkdir(outdir2); end
    fnp = fullfile(outdir2, sprintf('fig_antsweep_%s.png', link));
    try, exportgraphics(gcf, fnp, 'Resolution', 140); catch, saveas(gcf, fnp); end
    fprintf('[OK] 频响图: %s\n', fnp);
    fprintf('################################################################\n\n');
end


function [evm, ber, snrDb, symRx, dtBest] = rx_quality_light(iq, preSym, L, rrc, nPre, blkStep)
%RX_QUALITY_LIGHT  轻量版: 只做起点穷举 + EVM (与主脚本同逻辑)
    preSym = preSym(:); nSymBlk = numel(preSym);
    d  = floor(numel(rrc)/2);
    mf = conv(iq(:), rrc); mf = mf(d+1 : d+numel(iq));
    span = blkStep;
    if span > numel(mf) - blkStep, span = max(1, numel(mf)-blkStep); end
    evm = NaN; ber = NaN; snrDb = NaN; symRx = []; dtBest = 0;
    bestE = Inf;
    for off = 1:span
        idxAll = zeros(nSymBlk*nPre,1); nb = 0;
        for k = 0:(nPre-1)
            ii = (off + k*blkStep) + (0:(nSymBlk-1))*L;
            idxAll(nb+1:nb+nSymBlk) = ii(:); nb = nb + nSymBlk;
        end
        if any(idxAll<1) || any(idxAll>numel(mf)), continue; end
        Rs = reshape(mf(round(idxAll)), nSymBlk, nPre);
        idealM = repmat(preSym,1,nPre);
        al = sum(conj(idealM).*Rs,1) ./ sum(abs(idealM).^2,1);
        if any(abs(al)<1e-9), continue; end
        RsEq = Rs ./ repmat(al, nSymBlk, 1);
        err = RsEq - idealM;
        e = sqrt(mean(abs(err(:)).^2)/mean(abs(idealM(:)).^2))*100;
        if e < bestE, bestE = e; dtBest = off; symRx = RsEq(:); end
    end
    if isfinite(bestE)
        evm = bestE; snrDb = 20*log10(100/max(evm,eps)); ber = 0;
    end
end
