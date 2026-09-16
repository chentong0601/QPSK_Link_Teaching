function [rxBytes, stats] = e4_sim_link(txBytes, params, rrc, scrambler, opt)
%E4_SIM_LINK  E4 系列公共仿真链路: 内容字节流 -> 分片 -> QPSK -> 信道 -> 物理层 -> 重组
%
%   把内容经完整收发链路走一遍, 返回重组后的字节流与统计量。
%   四类内容共用本函数:
%     E4-TXT 文字 (UTF-8 字节流)
%     E4-IMG 图片 (JPEG 码流)
%     E4-VID 视频 (逐帧 JPEG, 调用方循环)
%     E4-AUD 音频 (PCM 字节流, **必须分块传入**, 见下)
%
%   用法:
%     params = init_params;
%     rrc = rcosdesign(params.RollOff, params.RRCSpan, params.SamplesPerSym, 'sqrt');
%     [~, scrambler, ~] = gen_frame_sequences(params);
%     opt.EbN0dB = 12; opt.freqOffset = 320;
%     [rxBytes, stats] = e4_sim_link(txBytes, params, rrc, scrambler, opt);
%
%   输入:
%     txBytes : uint8 列向量 (单段) 或 **cell 数组 (多段)**
%               ★ 单段长度受协议限制: >255 片 (14790 B) 会触发 video_slicer 报错。
%                 长内容 (如整段音频) 必须切分为 ≤14790 B 的多段传入 cell,
%                 每段独立成帧 (帧号 0,1,2,...), 重组端按帧号自动区分。
%     params / rrc / scrambler : 物理层对象 (调用方初始化一次即可复用)
%     opt.EbN0dB     : 仿真信噪比 dB (默认 12)
%     opt.freqOffset : 载波频偏 Hz (默认 320)
%     opt.dropFrac   : 模拟丢片率 0~1 (默认 0), 用于验证容错/降级行为
%     opt.verbose    : 打印链路小结 (默认 false)
%
%   输出:
%     rxBytes : uint8 列向量, 按段顺序拼接的重组结果 (失败时可能短于输入)
%     stats   : nSeg / nSlices / nFrames / txBytes / rxBytes / nFramesOK /
%               nFramesDrop / nDropSim / EbN0dB / freqOffset / txTime / rxTime /
%               sigDur / ok

    if nargin < 5 || isempty(opt), opt = struct(); end
    if ~isfield(opt, 'EbN0dB'),     opt.EbN0dB = 12;       end
    if ~isfield(opt, 'freqOffset'), opt.freqOffset = 320;  end
    if ~isfield(opt, 'verbose'),    opt.verbose = false;   end
    if ~isfield(opt, 'dropFrac'),   opt.dropFrac = 0;      end

    L  = params.SamplesPerSym;
    bp = params.bitsPerSym;

    %% ===== 归一化输入: 单段 -> cell =====
    if iscell(txBytes)
        segsIn = txBytes(:).';
    else
        segsIn = {uint8(txBytes(:))};
    end

    %% ===== 1. 发射: 逐段分片 -> 组帧 -> 基带成形 =====
    t0 = tic;
    plSeg  = cell(1, numel(segsIn));
    nBytes = 0;
    totSlice = 0;
    for si = 1:numel(segsIn)
        seg = uint8(segsIn{si}(:));
        [plSeg{si}, siInfo] = video_slicer(seg, mod(si-1, 256));  % 帧号递增
        nBytes   = nBytes + numel(seg);
        totSlice = totSlice + siInfo.totalSlices;
    end
    pl = horzcat(plSeg{:});          % 所有段的分片横向拼接
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
    wave = vertcat(segs{:});
    txTime = toc(t0);

    %% ===== 2. 信道: 载波频偏 + AWGN =====
    nn = (0:numel(wave)-1).';
    wave = wave .* exp(1j*2*pi*opt.freqOffset*nn/params.SampleRate);
    sg = sqrt(Es / (2 * 10^(opt.EbN0dB/10) * bp));
    wave = wave + sg * (randn(size(wave)) + 1j*randn(size(wave)));

    %% ===== 3. 接收: 物理层 =====
    t1 = tic;
    [pbs, ~] = rx_receiver(wave, params, scrambler, rrc, nSlice);
    rxTime = toc(t1);

    %% ===== 4. 重组 (可选: 模拟丢片) =====
    nDropSim = 0;
    if opt.dropFrac > 0 && ~isempty(pbs)
        keep = rand(numel(pbs), 1) > opt.dropFrac;
        nDropSim = sum(~keep);
        pbs = pbs(keep);
    end
    rst = video_reassembler();
    rxSegs = {};
    for i = 1:numel(pbs)
        [rst, done, jb] = video_reassembler(rst, pbs{i});
        if done
            rxSegs{end+1} = uint8(jb(:)); %#ok<AGROW>
        end
    end
    if isempty(rxSegs)
        rxBytes = uint8([]);
    else
        rxBytes = vertcat(rxSegs{:});
    end

    %% ===== 统计 =====
    stats = struct( ...
        'nSeg',        numel(segsIn), ...
        'nSlices',     totSlice, ...
        'nFrames',     nSlice, ...
        'txBytes',     nBytes, ...
        'rxBytes',     numel(rxBytes), ...
        'nFramesOK',   rst.nFramesOK, ...
        'nFramesDrop', rst.nFramesDrop, ...
        'nDropSim',    nDropSim, ...
        'EbN0dB',      opt.EbN0dB, ...
        'freqOffset',  opt.freqOffset, ...
        'txTime',      txTime, ...
        'rxTime',      rxTime, ...
        'sigDur',      numel(wave) / params.SampleRate, ...
        'ok',          isequal(rxBytes, vertcat(segsIn{:})));

    if opt.verbose
        fprintf('    [链路] %d 段 / %d B -> %d 片 / %d 传输帧 | 收 %d B | %s\n', ...
            numel(segsIn), nBytes, totSlice, nSlice, numel(rxBytes), ...
            tern(stats.ok, '字节完全一致', '字节不一致'));
    end
end

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end
