function main_e4_rxperf(link, varargin)
%MAIN_E4_RXPERF  接收机性能摸底 —— 扫 RxGain 测 EVM / BER / SNR (浴缸曲线)
%
%   为什么需要本脚本:
%     现有 E4 业务实验只产出"业务可用性"(帧成功率/PSNR/波形相关),
%     缺少接收机评价的【核心指标】: EVM / 星座图 / 灵敏度。
%     本脚本发射【纯前导】(收发双方已知的 QPSK 序列), 接收后与理想符号
%     直接比对, 得到【判决无关】的严格 EVM —— 这是接收机性能的标准评价方式。
%
%   参考: IET Electronics Letters "OTA testing of near-field and far-field
%         communication links" (同为 PlutoSDR), 其核心图即为 EVM vs RxGain
%         的"浴缸曲线": 低增益端受噪声主导, 高增益端受饱和失真主导。
%
%   用法 (必须在 MATLAB GUI 中运行):
%     main_e4_rxperf('coax')
%     main_e4_rxperf('short')
%     main_e4_rxperf('long')
%     main_e4_rxperf('coax', 'gains', 0:5:50)       % 自定义增益档
%     main_e4_rxperf('coax', 'nRep', 2)             % 每档采集周期数
%
%   产物:
%     results/e4/rxperf/rxperf_<link>_<ts>.mat   每档 EVM/BER/SNR + 星座点
%     plots/e4/fig_evm_bathtub_<link>.png        单张浴缸曲线 (可独立引用)

    if nargin < 1 || isempty(link), link = 'coax'; end
    validLink = {'coax', 'short', 'long', 'sim'};
    if ~ismember(link, validLink)
        error('link 必须是 %s 之一', strjoin(validLink, ' / '));
    end

    % ---- 可选参数 ----
    opt.gains  = 0:5:50;      % 待扫 RxGain
    opt.nRep   = 2;           % 每档抓取周期数
    opt.txGain = -20;
    opt.nPre   = 12;          % 每次发射的前导符号重复块数
    opt.link   = link;
    opt.selfTest = false;     % ★ true = 用合成信号自检 EVM 计算, 不接硬件
    for i = 1:2:numel(varargin)
        if i+1 <= numel(varargin), opt.(varargin{i}) = varargin{i+1}; end
    end

    thisDir = fileparts(mfilename('fullpath'));
    cd(fileparts(thisDir));
    addpath('config'); addpath('transmitter'); addpath('receiver');
    addpath('sync'); addpath('video'); addpath('experiments');

    params = init_params;
    L   = params.SamplesPerSym;
    bp  = params.bitsPerSym;
    rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
    [preBits, ~, preSym] = gen_frame_sequences(params);

    %% ===== 1. 组"纯前导"波形 =====
    % 只发前导符号 (无帧头/载荷), 便于接收端直接与已知序列比对
    % ★ 每块后加 guardLen 个零作为保护段 —— 接收端必须知道此长度才能【按块采样】!
    %   (符号在时间上是分块的, 块间有保护段; 误按"连续符号"采样会导致整块错位)
    blkBits  = preBits(:);
    guardLen = 80;

    % ★★ 块周期必须用【实际波形长度】计算, 不能用 numel(preSym)*L !
    %   tx_baseband 输出长度 = 符号数*L + 滤波器长度 - 1, 含 RRC 拖尾。
    %   本次: 32*4 + 25 - 1 = 152 (而非 128), 差 24 = numel(rrc)-1。
    %   若漏掉拖尾, 块周期会算成 208 而实际是 232 ⇒ 每块累积错位 ⇒ EVM 全错。
    [w0, ~]  = tx_baseband(preSym(:), L, rrc);
    wLen     = numel(w0);                          % 单块波形实际长度 (含拖尾)
    blkWave  = [];
    for k = 1:opt.nPre
        w = w0 * 0.9 / max(abs(w0));
        blkWave = [blkWave; w; zeros(guardLen, 1)]; %#ok<AGROW>
    end
    nPreSymPerBlk = numel(preSym);
    blkStep       = wLen + guardLen;               % ★ 块周期 (含拖尾)
    fprintf('  单块波形 %d 采样 (=%d符号 x %d + 滤波器拖尾 %d), 保护 %d, 块周期 %d\n', ...
            wLen, nPreSymPerBlk, L, numel(rrc)-1, guardLen, blkStep);

    fprintf('\n');
    fprintf('################################################################\n');
    fprintf('#   E4 接收机性能摸底 (EVM/BER/SNR) —— link = %s\n', link);
    fprintf('################################################################\n');
    fprintf('  前导符号/块 %d, 重复 %d 块, 每块 %.4f s\n', ...
            nPreSymPerBlk, opt.nPre, numel(blkWave)/params.SampleRate);
    fprintf('  扫描 RxGain: %s\n', mat2str(opt.gains));
    fprintf('  TxGain = %d dB\n\n', opt.txGain);

    if strcmp(link, 'sim')
        fprintf(2, '[!] sim 模式请用仿真脚本, 本脚本面向硬件。\n');
        return;
    end

    %% ===== 1.5 自检: 用合成信号验证 EVM 计算 (不接硬件) =====
    %   目的: 在接硬件前确认"同步+抽样+EVM"这条链是对的, 避免无效的硬件轮次。
    %   判据: 干净回环 EVM 应 ≈ 0; 加噪后 EVM 应与设定 SNR 自洽。
    if opt.selfTest
        fprintf('\n===== 自检模式 (合成信号, 不接硬件) =====\n');
        Es = mean(abs(blkWave).^2);

        % ① 干净回环: 直接把发射波形当作接收 IQ
        [e1, b1, s1, ~, t1] = rx_quality(blkWave, preSym, preBits, L, rrc, params, opt.nPre, blkStep);
        fprintf('  ① 干净回环      : EVM %8.4f %%  BER %.3e  SNR %6.2f dB  定时 %+d\n', e1, b1, s1, t1);

        % ② 加噪 (设定 SNR = 20 dB)
        snrSet = 20; rng(7);
        np = sqrt(Es / 10^(snrSet/10));
        iqN = blkWave + np*(randn(size(blkWave)) + 1j*randn(size(blkWave)))/sqrt(2);
        [e2, b2, s2, ~, t2] = rx_quality(iqN, preSym, preBits, L, rrc, params, opt.nPre, blkStep);
        fprintf('  ② 加噪 %2d dB    : EVM %8.4f %%  BER %.3e  SNR %6.2f dB  定时 %+d\n', snrSet, e2, b2, s2, t2);

        % ③ 加噪 + 频偏 300 Hz
        nn = (0:numel(blkWave)-1).';
        iqF = iqN .* exp(1j*2*pi*300*nn/params.SampleRate);
        [e3, b3, s3, ~, t3] = rx_quality(iqF, preSym, preBits, L, rrc, params, opt.nPre, blkStep);
        fprintf('  ③ 上+频偏 300Hz : EVM %8.4f %%  BER %.3e  SNR %6.2f dB  定时 %+d\n', e3, b3, s3, t3);

        fprintf('\n  ---- 判据 ----\n');
        fprintf('  ① 应 < 1%% (理想情况≈0)  ② 应约 %d%% (SNR=%d dB)  ③ 与②相近\n', ...
                round(100/10^(snrSet/20)), snrSet);
        if e1 < 5
            fprintf('  [OK] 自检通过: EVM 计算链正常, 可以接硬件运行。\n');
        else
            fprintf(2, '  [!!] 自检失败: 干净回环 EVM = %.2f%% 过大, 同步/抽样仍有问题。\n', e1);
        end
        fprintf('  (自检完成, 未访问硬件)\n\n');
        return;
    end

    %% ===== 2. 设备自检 =====
    fprintf('检查 Pluto 设备 ...\n');
    radios = [];
    try, radios = findPlutoRadio(); catch, end
    if isempty(radios)
        fprintf(2, '\n[!] 未发现 Pluto 设备, 中止。请先执行 clear all 后重试。\n');
        return;
    end
    fprintf('  发现 %d 台 Pluto\n', numel(radios));

    %% ===== 3. 扫增益 =====
    nG = numel(opt.gains);
    R = struct('gain', {}, 'evm', {}, 'ber', {}, 'snr', {}, ...
               'pwr', {}, 'nSym', {}, 'sym', {}, 'dt', {});
    IQall  = cell(1, nG);      % 暂存全部档位 IQ (11 档 × 5568 采样 ≈ 1 MB, 可接受)
    gainsV = nan(1, nG);       % 已采到的档位 (可能提前 break)
    nFail = 0;
    for gi = 1:nG
        g = opt.gains(gi);
        fprintf('\n----- RxGain = %2d dB -----\n', g);
        o.mode = 'hw'; o.link = link;
        o.txGain = opt.txGain; o.rxGain = g;
        o.nRep = opt.nRep; o.verbose = false;
        try
            [iq, st] = e4_hw_rawtxrx(blkWave, params, o);   % ★ 裸收发, 返回原始 IQ
            nFail = 0;
            [evm, ber, snrDb, symRx, dtBest] = rx_quality(iq, preSym, preBits, L, rrc, params, opt.nPre, blkStep);
            % ★ sym 字段必须用 { } 包装: 否则 struct() 会把向量"广播"成 struct 数组,
            %   再赋值给 R(end+1) 会报"数组的大小不兼容" (实测踩过)
            R(end+1) = struct('gain', g, 'evm', evm, 'ber', ber, 'snr', snrDb, ...
                              'pwr', st.rxPowerDbfs, 'nSym', numel(symRx), ...
                              'sym', {symRx}, 'dt', dtBest); %#ok<AGROW>
            IQall{numel(R)} = iq;     % ★ 用 R 的长度作索引, 避免中途失败导致错位
            gainsV(gi) = g;
            fprintf('  EVM %6.2f %%  | BER %.3e | SNR %5.2f dB | 功率 %6.2f dBFS | %d 符号 | 定时 %+d\n', ...
                    evm, ber, snrDb, st.rxPowerDbfs, numel(symRx), dtBest);
        catch ME
            nFail = nFail + 1;
            fprintf(2, '  失败: %s\n', ME.message);
            if nFail >= 3
                fprintf(2, '\n[!] 连续 %d 档失败, 停止扫描。\n', nFail);
                break;
            end
        end
    end

    if isempty(R)
        fprintf(2, '\n[!] 无有效数据。\n'); return;
    end

    %% ===== 4. 找最优增益 (EVM 最小) =====
    [evmMin, ib] = min([R.evm]);
    fprintf('\n===== 结果汇总 =====\n');
    fprintf('%8s %10s %13s %10s %12s %7s\n', 'RxGain', 'EVM(%)', 'BER', 'SNR(dB)', '功率(dBFS)', '定时');
    fprintf('%s\n', repmat('-', 1, 68));
    for i = 1:numel(R)
        fprintf('%6d dB %10.2f %13.3e %10.2f %12.2f %+7d\n', ...
                R(i).gain, R(i).evm, R(i).ber, R(i).snr, R(i).pwr, R(i).dt);
    end
    fprintf('%s\n', repmat('-', 1, 68));
    fprintf('★ 最优 RxGain = %d dB (EVM = %.2f %%, SNR = %.2f dB)\n', ...
            R(ib).gain, evmMin, R(ib).snr);

    %% ===== 5. 落盘 =====
    outdir = fullfile('results', 'e4', 'rxperf');
    if ~isfolder(outdir), mkdir(outdir); end
    tsTag = datestr(now, 'yyyymmdd_HHMMSS');
    % ★ 同样逐字段赋值 (gains / 向量字段会触发 struct 广播)
    cfg.link       = link;
    cfg.mode       = 'hw';
    cfg.txGain     = opt.txGain;
    cfg.gains      = opt.gains;
    cfg.nRep       = opt.nRep;
    cfg.nPre       = opt.nPre;
    cfg.centerFreq = params.CenterFrequency;
    cfg.sampleRate = params.SampleRate;
    cfg.timestamp  = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    % ★ 逐字段赋值, 不用 struct(...) —— 后者遇到向量字段会广播成 struct 数组
    metrics.evm      = [R.evm];
    metrics.ber      = [R.ber];
    metrics.snr      = [R.snr];
    metrics.gain     = [R.gain];
    metrics.pwr      = [R.pwr];
    metrics.dt       = [R.dt];
    metrics.gainBest = R(ib).gain;
    metrics.evmBest  = evmMin;
    metrics.snrBest  = R(ib).snr;

    raw.symBest = R(ib).sym;
    raw.preSym  = preSym;
    % ★ 挑代表性 IQ 存档: EVM 最小的 3 档 + 首档 + 末档 (便于离线诊断同步)
    ord  = 1:numel(R);
    [~, srt] = sort([R.evm]);
    pick = unique([srt(1:min(3, numel(srt))), 1, numel(R)]);
    raw.iqGains = [R(pick).gain];
    raw.iqVals  = IQall(pick);        % cell: 与 pick 一一对应

    fn = fullfile(outdir, sprintf('rxperf_%s_%s.mat', link, tsTag));
    save(fn, 'cfg', 'metrics', 'raw', '-v7.3');
    fprintf('[OK] 数据已存 %s\n', fn);

    %% ===== 6. 单张浴缸曲线 =====
    plot_bathtub(link, [R.gain], [R.evm], [R.snr]);

    fprintf('################################################################\n\n');
end


function [evm, ber, snrDb, symRx, dtBest] = rx_quality(iq, preSym, preBits, L, rrc, params, nPre, blkStep)
%RX_QUALITY  由接收 IQ 计算 EVM / BER / SNR (与理想前导序列比对, 判决无关)
%
%   ★★ 关键: 符号是【分块】的, 不是连续的!
%      发射波形 = [前导][保护80][前导][保护80]...
%      blkStep (块周期) 由调用方按【实际波形长度 + 保护段】算好传入 ——
%      不要在此处重算, 否则容易漏掉 RRC 拖尾 (numel(rrc)-1) 导致累积错位。
%      ★ 此前所有失败方案的共同错误: 假设符号连续, 或块周期漏算拖尾。
%        自检"干净回环 EVM≈650%"即由此暴露 (与噪声无关)。
    preSym = preSym(:);
    nSymBlk = numel(preSym);
    nPreSym = nSymBlk * nPre; %#ok<NASGU>

    % ---- 匹配滤波 (收发共用 rrc, 故直接卷积; d = 群延迟) ----
    d  = floor(numel(rrc)/2);
    mf = conv(iq(:), rrc);
    mf = mf(d+1 : d+numel(iq));

    % ---- 起点搜索: 在 [1, blkStep] 内穷举, 以 EVM 择优 ----
    %   正确起点必落在一个块周期内; EVM 是真实失真度量 ⇒ 穷举必找到对齐。
    span = blkStep;
    if span > numel(mf) - blkStep, span = max(1, numel(mf) - blkStep); end
    dtBest = 0; evmBest = Inf;
    symBest = []; nBlkBest = 0; alphaBest = [];
    for off = 1:span
        [ev, symRx, nBlk, alpha] = evm_at(mf, off, L, nSymBlk, nPre, blkStep, preSym);
        if ~isnan(ev) && ev < evmBest
            evmBest = ev; dtBest = off;
            symBest = symRx; nBlkBest = nBlk; alphaBest = alpha;
        end
    end

    if isinf(evmBest) || isempty(symBest)
        evm = NaN; ber = NaN; snrDb = NaN; symRx = []; return;
    end

    evm   = evmBest;
    symRx = symBest;
    snrDb = 20*log10(100 / max(evm, eps));

    % ---- BER: 用最佳定时下的均衡符号判决反比特 ----
    if nBlkBest >= 1 && ~isempty(alphaBest)
        % ★ symBest 是一维列向量 (nSymBlk*nBlk × 1), 必须 reshape 成
        %   nSymBlk × nBlk 才能与 alphaBest (1 × nBlk) 对齐做逐块归一化
        RsMat  = reshape(symBest, nSymBlk, nBlkBest);
        RsEq   = RsMat ./ repmat(alphaBest, nSymBlk, 1);
        rxIdx  = pskdemod(RsEq(:), params.M, 0, 'gray');
        rxBits = reshape(de2bi(rxIdx, params.bitsPerSym, 2, 'left-msb').', [], 1);
        nb = min(numel(rxBits), numel(preBits)*nBlkBest);
        if nb > 0
            pb  = repmat(preBits(:), nBlkBest, 1);
            ber = mean(rxBits(1:nb) ~= pb(1:nb));
        else
            ber = NaN;
        end
    else
        ber = NaN;
    end
end


function [evm, symRx, nBlk, alpha] = evm_at(mf, off, L, nSymBlk, nPre, blkStep, preSym)
%EVM_AT  在给定起点下【按块】抽样并计算 EVM
%
%   ★ 按块采样 (关键): 第 k 块的起点 = off + (k-1)*blkStep, 块内取 nSymBlk 个符号。
%     若误写成"连续采 nSymBlk*nPre 个符号", 会跨过块间的保护段 ⇒ 符号错位,
%     表现为 EVM 极高 (自检干净回环 633%) 且 BER≈0.5。
    evm = NaN; symRx = []; nBlk = 0; alpha = [];
    idxAll = zeros(nSymBlk*nPre, 1);
    nb = 0;
    for k = 0:(nPre-1)
        base = off + k*blkStep;
        ii = base + (0:(nSymBlk-1))*L;
        idxAll(nb+1 : nb+nSymBlk) = ii(:);
        nb = nb + nSymBlk;
    end
    idxAll = round(idxAll);
    keep = idxAll >= 1 & idxAll <= numel(mf);
    if nnz(keep) < nSymBlk
        return;
    end
    % 只保留完整的块 (若末尾块越界则丢弃整块, 避免半块污染 reshape)
    nBlk = floor(nnz(keep) / nSymBlk);
    if nBlk < 1
        return;
    end
    % 逐块取, 跳过越界的块
    Rs = zeros(nSymBlk, nBlk);
    c = 0;
    for k = 0:(nPre-1)
        s0 = k*nSymBlk;
        seg = idxAll(s0+1 : s0+nSymBlk);
        if all(seg >= 1 & seg <= numel(mf)) && c < nBlk
            c = c + 1;
            Rs(:, c) = mf(seg);
        end
    end
    if c < nBlk, nBlk = c; Rs = Rs(:, 1:c); end
    if nBlk < 1, return; end
    symRx = Rs(:);

    % 逐块估计复增益 (含信道幅度/相位与残余频偏) 并补偿
    idealM = repmat(preSym, 1, nBlk);
    alpha  = sum(conj(idealM) .* Rs, 1) ./ sum(abs(idealM).^2, 1);
    if any(abs(alpha) < 1e-9)
        return;
    end
    RsEq = Rs ./ repmat(alpha, nSymBlk, 1);

    err = RsEq - idealM;
    evm = sqrt(mean(abs(err(:)).^2) / mean(abs(idealM(:)).^2)) * 100;
end


function plot_bathtub(link, gains, evm, snr)
%PLOT_BATHTUB  单张浴缸曲线 (EVM vs RxGain, 附 SNR 次轴) —— 独立成图
    figure('Position', [80 80 760 480], 'Color', 'w', 'Visible', 'on');
    yyaxis left
    plot(gains, evm, '-o', 'LineWidth', 1.8, 'MarkerSize', 7, 'MarkerFaceColor', 'auto');
    ylabel('RMS EVM (%)', 'FontSize', 12);
    grid on;
    yyaxis right
    plot(gains, snr, '-s', 'LineWidth', 1.4, 'MarkerSize', 6);
    ylabel('SNR (dB)', 'FontSize', 12);
    xlabel('RxGain (dB)', 'FontSize', 12);
    title(sprintf('接收机 EVM 浴缸曲线 —— %s', link), 'FontSize', 13);
    legend({'RMS EVM','SNR'}, 'Location', 'north', 'FontSize', 10);

    outdir = fullfile('plots', 'e4');
    if ~isfolder(outdir), mkdir(outdir); end
    fn = fullfile(outdir, sprintf('fig_evm_bathtub_%s.png', link));
    try
        exportgraphics(gcf, fn, 'Resolution', 140);
    catch
        saveas(gcf, fn);
    end
    fprintf('[OK] 浴缸曲线: %s\n', fn);
end
