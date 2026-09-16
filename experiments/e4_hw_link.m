function [rxBytes, stats, rxData] = e4_hw_link(txBytes, params, rrc, scrambler, opt)
%E4_HW_LINK  硬件在环收发 —— 单板自发自收 / 双板分置收发
%
%   把内容分片组帧成基带波形, 经 Pluto 循环发射, 同步采集, 离线解码重组。
%
%   ⚠️ 必须在 MATLAB GUI 中运行!
%      (-batch 模式下 Support Package 路径未注册, sdrtx/sdrrx 不可用)
%
%   用法:
%     opt.link = 'coax'; opt.rxGain = 30; opt.txGain = -20;
%     [rxBytes, stats] = e4_hw_link(txBytes, params, rrc, scrambler, opt);
%     [~, ~, rxIQ]   = e4_hw_link(...);   % ★ 第 3 输出: 原始 IQ (供 EVM/星座图分析)
%
%   输入:
%     txBytes : uint8 列向量 (单段) 或 cell 数组 (多段; 每段独立成帧)
%     params / rrc / scrambler : 物理层对象 (调用方初始化一次)
%     opt.link     : 'coax' | 'short' | 'long'  (仅用于标记与落盘, 不影响收发逻辑)
%     opt.txGain   : 发射增益 dB (默认 -20)
%     opt.rxGain   : 接收增益 dB (默认 30)
%     opt.nRep     : 抓取几个发射周期 (默认 3)
%     opt.spf      : SamplesPerFrame (默认 8192)
%     opt.devTx    : 发射设备 ID (默认 'usb:0')
%     opt.devRx    : 接收设备 ID (默认 = devTx, 即单板自发自收)
%                    ★ 双板实验时把 devRx 指向另一块板即可
%     opt.verbose  : 打印过程 (默认 true)
%
%   输出:
%     rxBytes : uint8 列向量, 按段顺序重组的结果
%     stats   : 与 e4_sim_link 同名字段, 另加
%               link / txGain / rxGain / rxPowerDbfs / freqEstMean / freqEstStd

    if nargin < 5 || isempty(opt), opt = struct(); end
    if ~isfield(opt, 'link'),    opt.link = 'hw';    end
    if ~isfield(opt, 'txGain'),  opt.txGain = -20;   end
    if ~isfield(opt, 'rxGain'),  opt.rxGain = 30;    end
    if ~isfield(opt, 'nRep'),    opt.nRep = 3;       end
    if ~isfield(opt, 'spf'),     opt.spf = 8192;     end
    if ~isfield(opt, 'devTx'),   opt.devTx = 'usb:0';end
    if ~isfield(opt, 'devRx'),   opt.devRx = opt.devTx; end   % 默认单板
    if ~isfield(opt, 'verbose'), opt.verbose = true; end

    L  = params.SamplesPerSym;
    bp = params.bitsPerSym;

    dualBoard = ~strcmp(opt.devTx, opt.devRx);

    %% ===== 1. 分片 -> 组帧 -> 基带成形 =====
    if iscell(txBytes)
        segsIn = txBytes(:).';
    else
        segsIn = {uint8(txBytes(:))};
    end

    plSeg = cell(1, numel(segsIn));
    nBytes = 0; totSlice = 0;
    for si = 1:numel(segsIn)
        seg = uint8(segsIn{si}(:));
        [plSeg{si}, siInfo] = video_slicer(seg, mod(si-1, 256));
        nBytes   = nBytes + numel(seg);
        totSlice = totSlice + siInfo.totalSlices;
    end
    pl = horzcat(plSeg{:});
    nSlice = size(pl, 2);

    segs = cell(1, nSlice);
    Es = [];
    for i = 1:nSlice
        fSym = tx_frame(pl(:, i), params, 0, mod(i-1, 256));
        [w, ~] = tx_baseband(fSym, L, rrc);
        w = w * 0.9 / max(abs(w));
        if i == 1, Es = L * mean(abs(w).^2); end
        segs{i} = [w; zeros(80, 1)];
    end
    wave    = vertcat(segs{:});
    waveLen = numel(wave);

    if opt.verbose
        fprintf('    [硬件链路] link=%s%s | %d 段 / %d B -> %d 片 / %d 传输帧\n', ...
            opt.link, tern(dualBoard, ' (双板)', ' (单板)'), ...
            numel(segsIn), nBytes, totSlice, nSlice);
        fprintf('               波形 %d 采样 = %.3f s/周期, 抓取 %d 周期\n', ...
            waveLen, waveLen/params.SampleRate, opt.nRep);
    end

    %% ===== 2. 硬件收发 (确保异常时也释放) =====
    tx = []; rx = []; rxData = [];
    t0 = tic;
    try
        % ★ 单板用最简构造 (与已验证的 P6 脚本一致, 避免 RadioID 语法差异)
        if dualBoard
            tx = sdrtx('Pluto', 'RadioID', opt.devTx);
        else
            tx = sdrtx('Pluto');
        end
        tx.CenterFrequency    = params.CenterFrequency;
        tx.BasebandSampleRate = params.SampleRate;
        tx.Gain               = opt.txGain;
        tx.OutputDataType     = 'double';
        transmitRepeat(tx, wave);
        if opt.verbose, fprintf('               已开始循环发射 (TxGain=%d dB)\n', opt.txGain); end

        if dualBoard
            rx = sdrrx('Pluto', 'RadioID', opt.devRx);
        else
            rx = sdrrx('Pluto');
        end
        rx.CenterFrequency    = params.CenterFrequency;
        rx.BasebandSampleRate = params.SampleRate;
        rx.GainSource         = 'Manual';
        rx.Gain               = opt.rxGain;
        rx.SamplesPerFrame    = opt.spf;
        rx.OutputDataType     = 'double';

        % 丢弃前几块, 让 AGC/滤波器进入稳态, 避开起始瞬态
        for i = 1:3, rx(); end

        nBlk   = ceil(waveLen * opt.nRep / opt.spf);
        rxData = zeros(nBlk * opt.spf, 1);
        for i = 1:nBlk
            rxData((i-1)*opt.spf + 1 : i*opt.spf) = rx();
        end
        capT = toc(t0);
        if opt.verbose
            fprintf('               采集 %d 采样 (%.3f s), 用时 %.2f s\n', ...
                numel(rxData), numel(rxData)/params.SampleRate, capT);
        end
    catch ME
        fprintf(2, '[硬件失败] %s\n', ME.message);
        try, if ~isempty(rx), release(rx); end, catch, end
        try, if ~isempty(tx), release(tx); end, catch, end
        rethrow(ME);
    end

    % ★ 无论如何都要释放硬件, 否则下次连接会失败
    try, release(rx); catch, end
    try, release(tx); catch, end
    clear rx tx;

    %% ===== 3. 预处理 =====
    rxData = rxData - mean(rxData);                       % 去直流 (零中频偏置)
    rxPowerDbfs = 20*log10( sqrt(mean(abs(rxData).^2)) + eps );

    % ★ 饱和预警 (P1 教训: RxGain 过高会削顶, 引入非线性失真并使所有指标失真)
    if rxPowerDbfs > -3
        fprintf(2, '    [!] 接收功率 %.1f dBFS 已接近满量程, 很可能饱和!\n', rxPowerDbfs);
        fprintf(2, '        当前 RxGain = %d dB -> 建议降低, 或加衰减器\n', opt.rxGain);
    end

    %% ===== 4. 离线解码 =====
    [pbs, st] = rx_receiver(rxData, params, scrambler, rrc, nSlice * opt.nRep);

    %% ===== 5. 重组 =====
    % ★ 关键: transmitRepeat 是【循环发射】, 抓 nRep 个周期会重复收到同一批内容。
    %   若简单地把所有收齐的段依次拼接, 长度会变成 nRep 倍
    %   (实测: 326 B 文本 -> 978 B, 恰为 3 倍)。故按【段号】归位, 每段只取首次完整收到的。
    nSegWant = numel(segsIn);
    rxSegMap = cell(1, nSegWant);
    filled   = false(1, nSegWant);
    rst = video_reassembler();
    for i = 1:numel(pbs)
        fn  = double(pbs{i}(1));            % 分片头首字节 = 段号-1 (mod 256)
        sid = fn + 1;
        [rst, done, jb] = video_reassembler(rst, pbs{i});
        if done && sid >= 1 && sid <= nSegWant && ~filled(sid)
            rxSegMap{sid} = uint8(jb(:));
            filled(sid)   = true;
        end
    end
    nSegGot = sum(filled);
    if nSegGot > 0
        rxBytes = vertcat(rxSegMap{filled});
    else
        rxBytes = uint8([]);
    end

    %% ===== 6. 统计 =====
    fe = st.freqEsts;
    if isempty(fe)
        feMean = NaN; feStd = NaN;
    else
        feMean = mean(fe); feStd = std(fe);
    end

    stats = struct( ...
        'nSeg',        numel(segsIn), ...
        'nSegGot',     sum(filled), ...
        'nSlices',     totSlice, ...
        'nFrames',     nSlice, ...
        'txBytes',     nBytes, ...
        'rxBytes',     numel(rxBytes), ...
        'nFramesOK',   rst.nFramesOK, ...
        'nFramesDrop', rst.nFramesDrop, ...
        'nDropSim',    0, ...
        'link',        opt.link, ...
        'mode',        'hw', ...
        'txGain',      opt.txGain, ...
        'rxGain',      opt.rxGain, ...
        'dualBoard',   dualBoard, ...
        'rxPowerDbfs', rxPowerDbfs, ...
        'freqEstMean', feMean, ...
        'freqEstStd',  feStd, ...
        'sigDur',      numel(rxData) / params.SampleRate, ...
        'capTime',     capT, ...
        'ok',          isequal(rxBytes, vertcat(segsIn{:})));

    if opt.verbose
        fprintf('    [硬件链路] 接收功率 %.1f dBFS | 频偏 %.1f±%.1f Hz | 段 %d/%d | 收 %d B | %s\n', ...
            rxPowerDbfs, feMean, feStd, sum(filled), numel(segsIn), numel(rxBytes), ...
            tern(stats.ok, '字节完全一致', '字节不一致'));
    end
end

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end
