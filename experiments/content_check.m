function content_check()
%CONTENT_CHECK  素材体检 —— 扫描 content/, 报告规格与链路传输预估
%
%   用途: 在 content/{text,image,video,audio} 放好素材后运行本脚本,
%         得到每个素材的规格与"通过本链路传输"的预估(片数/帧数/耗时),
%         据此再生成对应的传输实验脚本。
%
%   用法:   >> content_check
%   输出:   屏幕汇总 + content/素材体检报告.md
%
%   依赖:   核心 MATLAB (imread / audioread / VideoReader), 无需额外工具箱
%
%   链路参数来源: 下方"链路常量"一节, 与 video_protocol.m + 物理层保持一致
%                (单传输帧载荷 62 B; 帧长 1208 采样 @ 1 MHz)

    thisDir  = fileparts(mfilename('fullpath'));   % .../QPSK_Link_Teaching/experiments
    projRoot = fileparts(thisDir);                 % .../QPSK_Link_Teaching
    cdir     = fullfile(projRoot, 'content');

    %% ===== 链路常量 =====
    % video_protocol.m 是分片协议的唯一真源; 不在 path 上时临时加入
    if exist('video_protocol', 'file') ~= 2
        addpath(fullfile(projRoot, 'video'));
    end
    try
        P = video_protocol();     % 62 B/帧, 头 4 B, 数据 58 B, 上限 255 片
    catch
        P = struct('PayloadBytes', 62, 'HeaderBytes', 4, 'DataBytes', 58, ...
                   'MaxSlices', 255, 'MaxFrameBytes', 255*58);
        fprintf(2, '[!] 未找到 video_protocol.m, 改用内联默认协议常量\n');
    end
    nSamp     = 1208;                 % 每传输帧采样数
    fs        = 1e6;                  % 采样率 1 MHz
    frameDur  = nSamp / fs;           % 单传输帧时长 = 1.208 ms
    thrBytes  = P.PayloadBytes / frameDur;   % 吞吐 ≈ 51.3 KB/s (≈ 410 kbps)

    fprintf('\n================ 素材体检 ================\n');
    fprintf('链路吞吐: %.1f KB/s (%.0f kbps)   单帧 %.3f ms   上限 %d 片/帧 (%d B)\n', ...
            thrBytes/1024, thrBytes*8/1000, frameDur*1e3, P.MaxSlices, P.MaxFrameBytes);

    if ~isfolder(cdir)
        fprintf(2, '\n[!] 未找到 content/ 目录。请先创建并放入素材。\n');
        return;
    end

    lines = {};   % 报告行
    lines{end+1} = '# 素材体检报告';
    lines{end+1} = '';
    lines{end+1} = sprintf('> 链路吞吐 %.1f KB/s，单传输帧载荷 %d B，帧时长 %.3f ms，单帧上限 %d 片（%d B）。', ...
                           thrBytes/1024, P.PayloadBytes, frameDur*1e3, P.MaxSlices, P.MaxFrameBytes);
    lines{end+1} = '';

    %% ===== 1) 文字 =====
    lines{end+1} = '## 1 文字素材 (text/)';
    lines{end+1} = '';
    d = dir(fullfile(cdir, 'text', '*.*'));
    d = d(~[d.isdir]);
    if isempty(d)
        fprintf('\n[文字] (空)\n');
        lines{end+1} = '_（空）_';
    else
        lines{end+1} = '| 文件 | 字节数 | 分片数 | 传输帧数 | 传输耗时 | 备注 |';
        lines{end+1} = '|------|-------|-------|---------|---------|------|';
        for k = 1:numel(d)
            nb  = d(k).bytes;
            sl  = ceil(nb / P.DataBytes);
            nfr = ceil(sl / P.MaxSlices);
            t   = sl * frameDur;
            note = '';
            if sl > P.MaxSlices, note = sprintf('超单帧上限，需拆 %d 帧', nfr); end
            fprintf('[文字] %-28s %8.1f KB  %5d 片  %6.2f s  %s\n', ...
                    d(k).name, nb/1024, sl, t, note);
            lines{end+1} = sprintf('| %s | %.1f KB | %d | %d | %.2f s | %s |', ...
                                   d(k).name, nb/1024, sl, nfr, t, note);
        end
    end
    lines{end+1} = '';

    %% ===== 2) 图片 =====
    lines{end+1} = '## 2 图片素材 (image/)';
    lines{end+1} = '';
    d = dir(fullfile(cdir, 'image', '*.*'));
    d = d(~[d.isdir]);
    if isempty(d)
        fprintf('\n[图片] (空)\n');
        lines{end+1} = '_（空）_';
    else
        lines{end+1} = '| 文件 | 原始尺寸 | 原始大小 | 预估压缩后 | 分片数 | 传输耗时 | 备注 |';
        lines{end+1} = '|------|---------|---------|-----------|-------|---------|------|';
        for k = 1:numel(d)
            try
                info = imfinfo(fullfile(cdir, 'image', d(k).name));
                sz   = sprintf('%dx%d', info(1).Width, info(1).Height);
            catch
                sz = '读取失败';
            end
            nbRaw = d(k).bytes;
            nfr   = ceil(nbRaw / P.MaxFrameBytes);
            sl    = ceil(nbRaw / P.DataBytes);
            t     = sl * frameDur;
            note  = '';
            if sl > P.MaxSlices, note = sprintf('超单帧上限，需跨 %d 帧拆分', nfr); end
            fprintf('[图片] %-28s %-11s %8.1f KB  ~%5d 片  %6.2f s  %s\n', ...
                    d(k).name, sz, nbRaw/1024, sl, t, note);
            lines{end+1} = sprintf('| %s | %s | %.1f KB | （实验时实测） | %d | %.2f s | %s |', ...
                                   d(k).name, sz, nbRaw/1024, sl, t, note);
        end
    end
    lines{end+1} = '';

    %% ===== 3) 视频 =====
    lines{end+1} = '## 3 视频素材 (video/)';
    lines{end+1} = '';
    d = dir(fullfile(cdir, 'video', '*.*'));
    d = d(~[d.isdir]);
    if isempty(d)
        fprintf('\n[视频] (空)\n');
        lines{end+1} = '_（空）_';
    else
        lines{end+1} = '| 文件 | 分辨率 | 时长 | 帧率 | 总帧数 | 建议抽帧 | 预估等效传输时长 |';
        lines{end+1} = '|------|-------|------|------|-------|---------|----------------|';
        for k = 1:numel(d)
            fp = fullfile(cdir, 'video', d(k).name);
            try
                vr = VideoReader(fp);
                W = vr.Width; H = vr.Height; dur = vr.Duration; fr = vr.FrameRate;
                nTot = floor(dur * fr);
            catch ME
                fprintf(2, '[视频] %s 读取失败: %s\n', d(k).name, ME.message);
                lines{end+1} = sprintf('| %s | 读取失败 | - | - | - | - | %s |', d(k).name, ME.message);
                continue;
            end
            % 建议抽帧: 目标 176x144 均衡档, 约 1.4 KB/帧 -> ~17 fps 可传
            tgtFps = 12;
            keep   = min(nTot, max(1, round(dur * tgtFps)));
            estB   = keep * 1400;                       % 保守 1.4 KB/帧
            tTx    = ceil(estB / P.DataBytes) * frameDur;
            fprintf('[视频] %-28s %dx%d  %.2f s  %.1f fps  %d 帧 -> 抽 %d 帧, 传输约 %.1f s\n', ...
                    d(k).name, W, H, dur, fr, nTot, keep, tTx);
            lines{end+1} = sprintf('| %s | %dx%d | %.2f s | %.1f | %d | %d | %.1f s |', ...
                                   d(k).name, W, H, dur, fr, nTot, keep, tTx);
        end
    end
    lines{end+1} = '';

    %% ===== 4) 语音 =====
    lines{end+1} = '## 4 语音素材 (audio/)';
    lines{end+1} = '';
    d = dir(fullfile(cdir, 'audio', '*.*'));
    d = d(~[d.isdir]);
    if isempty(d)
        fprintf('\n[语音] (空)\n');
        lines{end+1} = '_（空）_';
    else
        lines{end+1} = '| 文件 | 采样率 | 声道 | 时长 | 目标码率 | 码流大小 | 分片数 | 传输耗时 | 实时余量 |';
        lines{end+1} = '|------|-------|------|------|---------|---------|-------|---------|---------|';
        for k = 1:numel(d)
            fp = fullfile(cdir, 'audio', d(k).name);
            try
                info = audioinfo(fp);
                fsA = info.SampleRate; nCh = info.NumChannels; dur = info.Duration;
            catch ME
                fprintf(2, '[语音] %s 读取失败: %s\n', d(k).name, ME.message);
                lines{end+1} = sprintf('| %s | 读取失败 | - | - | - | - | - | - | %s |', d(k).name, ME.message);
                continue;
            end
            % 目标: 16 kHz 单声道 8 bit (可懂度足够, 码率 128 kbps < 链路 410 kbps)
            fsT   = 16000;
            bits  = 8;
            nByte = ceil(dur * fsT * bits / 8);
            sl    = ceil(nByte / P.DataBytes);
            tTx   = sl * frameDur;
            margin = tTx / max(dur, eps);       % <1 表示可实时传输
            fprintf('[语音] %-28s %d Hz %d 声道 %.2f s -> 16kHz/8bit %6.1f KB  %5d 片  传输 %.1f s  (耗时/时长=%.2f)\n', ...
                    d(k).name, fsA, nCh, dur, nByte/1024, sl, tTx, margin);
            lines{end+1} = sprintf('| %s | %d Hz | %d | %.2f s | 16 kHz/8 bit | %.1f KB | %d | %.1f s | x%.2f |', ...
                                   d(k).name, fsA, nCh, dur, nByte/1024, sl, tTx, margin);
        end
        lines{end+1} = '';
        lines{end+1} = '> 实时余量 < 1.0 表示**可实时传输**（传输耗时短于音频本身时长）。';
    end

    %% ===== 写报告 =====
    outFn = fullfile(cdir, '素材体检报告.md');
    fid = fopen(outFn, 'w', 'n', 'UTF-8');
    if fid > 0
        fwrite(fid, unicode2native(strjoin(lines, newline), 'UTF-8'), 'uint8');
        fclose(fid);
        fprintf('\n[OK] 报告已保存: %s\n', outFn);
    else
        fprintf(2, '[!] 报告写入失败: %s\n', outFn);
    end
    fprintf('==========================================\n\n');
end
