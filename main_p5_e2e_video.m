%% main_p5_e2e_video.m
% P5 仿真层端到端联调: 视频 -> JPEG/分片 -> QPSK物理层 -> 重组/解码 -> 视频
%
% 这是【第一次让视频真正走通物理层】。此前:
%   P2/E3 验证了视频链路(纯软件, 不经射频)
%   W7b  验证了物理层(但传的是文本)
% 本脚本把两者接起来, 在仿真信道(AWGN + 载波频偏)下端到端跑通。
%
% 产出: 视频帧还原对比图 + 传输层/视频层指标
% 用法: matlab -batch "main_p5_e2e_video"

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync'); addpath('video');
params = init_params;
P = video_protocol();
M = params.M; bp = params.bitsPerSym; L = params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

%% ===== 配置 =====
CFG.h = 144; CFG.w = 176;        % 视频分辨率 (E3 推荐的均衡档)
CFG.q = 50;                      % JPEG 质量
CFG.nVideo = 10;                 % 视频帧数
CFG.kind  = 'moving';            % 内容类型 (最接近真实视频)
CFG.EbN0dB = 12;
CFG.freqOffset = 320;

fprintf('\n################################################################\n');
fprintf('#   P5 仿真层端到端联调: 视频 over QPSK                              #\n');
fprintf('################################################################\n');
fprintf('视频: %dx%d, JPEG Q=%d, %d 帧, 内容=%s\n', ...
        CFG.w, CFG.h, CFG.q, CFG.nVideo, CFG.kind);
fprintf('信道: AWGN (Eb/N0=%d dB) + 载波频偏 %d Hz\n\n', CFG.EbN0dB, CFG.freqOffset);

%% ===== 1. 发射: 视频 -> JPEG -> 分片 -> QPSK 波形 =====
fprintf('===== 1. 发射端 =====\n');
txImgs = cell(1, CFG.nVideo);       % 原始视频帧 (用于 PSNR)
txSlices = [];                      % 每视频帧的片数
segs = {};                          % ★ 用 cell 收集波形段, 最后一次性拼接
                                    %   (原实现 wave=[wave; w; ...] 反复增长数组,
                                    %    476 次重新分配累计约 1.4 亿元素拷贝,
                                    %    是发射侧耗时的主要来源)
physFrameNum = 0;
t0 = tic;
for k = 1:CFG.nVideo
    % 先在 240x320 基准上生成, 再缩放到目标分辨率 (与 E3 标定口径一致)
    img = imresize(video_testframe(240, 320, CFG.kind, k), [CFG.h CFG.w]);
    txImgs{k} = img;

    jb = jpeg_encode(img, CFG.q);
    [pl, info] = video_slicer(jb, mod(k-1, 256));
    txSlices(k) = info.totalSlices;

    for i = 1:size(pl,2)
        fSym = tx_frame(pl(:,i), params, 0, mod(physFrameNum,256));
        [w, ~] = tx_baseband(fSym, L, rrc);
        w = w * 0.9/max(abs(w));
        if isempty(segs), Es = L*mean(abs(w).^2); end
        segs{end+1} = [w; zeros(80,1)]; %#ok<AGROW>
        physFrameNum = physFrameNum + 1;
    end
end
wave = vertcat(segs{:});            % ★ 一次性拼接
txTime = toc(t0);
fprintf('  视频帧: %d, 传输帧总数: %d (片数分布 %d~%d)\n', ...
        CFG.nVideo, physFrameNum, min(txSlices), max(txSlices));
fprintf('  波形长度: %d 采样 = %.3f s @1MHz\n', numel(wave), numel(wave)/params.SampleRate);
fprintf('  编码+组帧耗时: %.2f s (%.1f ms/传输帧)\n', txTime, txTime/physFrameNum*1000);

%% ===== 2. 信道 =====
nn = (0:numel(wave)-1).';
wave = wave .* exp(1j*2*pi*CFG.freqOffset*nn/params.SampleRate);
sg = sqrt(Es/(2*10^(CFG.EbN0dB/10)*bp));
wave = wave + sg*(randn(size(wave)) + 1j*randn(size(wave)));
fprintf('\n===== 2. 信道 =====\n  已注入频偏 %d Hz 与 AWGN (Eb/N0=%d dB)\n', ...
        CFG.freqOffset, CFG.EbN0dB);

%% ===== 3. 接收: 物理层 =====
fprintf('\n===== 3. 接收端 (物理层) =====\n');
t0 = tic;
[pbs, st] = rx_receiver(wave, params, scrambler, rrc, physFrameNum);
rxTime = toc(t0);
fprintf('  物理层解出: %d / %d 传输帧 (块数 %d), 耗时 %.2f s (%.1f ms/帧)\n', ...
        numel(pbs), physFrameNum, st.nBlocks, rxTime, rxTime/physFrameNum*1000);
fprintf('  单帧处理时延 = %.2f ms  (帧周期 %.3f ms) => %s\n', ...
        rxTime/physFrameNum*1000, 296/params.SampleRate*1000, ...
        pick(rxTime/physFrameNum*1000 < 296/params.SampleRate*1000, ...
             '【满足实时】','【未满足实时】'));

%% ===== 4. 重组 + 解码 (视频层) =====
fprintf('\n===== 4. 视频层重组与解码 =====\n');
rst = video_reassembler();
rxImgs = cell(1, CFG.nVideo);
rxPSNR = nan(1, CFG.nVideo);
nDecoded = 0;
for i = 1:numel(pbs)
    [rst, done, jb] = video_reassembler(rst, pbs{i});
    if done
        nDecoded = nDecoded + 1;
        if nDecoded <= CFG.nVideo
            try
                img = jpeg_decode(jb);
                rxImgs{nDecoded} = img;
                if isequal(size(img), size(txImgs{nDecoded}))
                    rxPSNR(nDecoded) = psnr8(txImgs{nDecoded}, img);
                end
            catch e
                fprintf('    视频帧 %d 解码失败: %s\n', nDecoded, e.message);
            end
        end
    end
end
fprintf('  完整重组视频帧: %d / %d\n', nDecoded, CFG.nVideo);
fprintf('  传输层统计: 收片 %d, 重复片 %d, 丢帧 %d\n', ...
        rst.nSlicesRecv, rst.nSlicesDup, rst.nFramesDrop);
ok = sum(~isnan(rxPSNR));
if ok > 0
    fprintf('  视频帧 PSNR: 均值 %.2f dB, 最小 %.2f dB, 最大 %.2f dB (%d 帧有效)\n', ...
            mean(rxPSNR(~isnan(rxPSNR))), min(rxPSNR(~isnan(rxPSNR))), ...
            max(rxPSNR(~isnan(rxPSNR))), ok);
end

%% ===== 5. 端到端指标 =====
sigDur = numel(wave)/params.SampleRate;
fprintf('\n===== 5. 端到端指标 =====\n');
fprintf('  信号时长          : %.3f s\n', sigDur);
fprintf('  视频帧完整率      : %.1f%% (%d/%d)\n', nDecoded/CFG.nVideo*100, nDecoded, CFG.nVideo);
fprintf('  等效端到端帧率    : %.1f fps  (视频帧数 / 信号时长)\n', nDecoded/sigDur);
fprintf('  发射侧耗时        : %.2f s (%.1f%% 于信号时长)\n', txTime, txTime/sigDur*100);
fprintf('  接收侧耗时        : %.2f s (%.1f%% 于信号时长)\n', rxTime, rxTime/sigDur*100);
fprintf('  => 软硬件处理%s跟上链路速率\n', pick(txTime < sigDur && rxTime < sigDur, '可以', '**无法**'));

%% ===== 6. 可视化 =====
nShow = min(4, nDecoded);
if nShow > 0
    f = figure('Position',[80 80 900 620],'Color','w');
    for i = 1:nShow
        subplot(nShow, 2, 2*i-1);
        imshow(txImgs{i}); title(sprintf('发送帧 %d', i), 'FontSize',10);
        subplot(nShow, 2, 2*i);
        if ~isempty(rxImgs{i}) && ~isnan(rxPSNR(i))
            imshow(rxImgs{i});
            title(sprintf('接收帧 %d  (PSNR %.1f dB)', i, rxPSNR(i)), 'FontSize',10);
        else
            axis off; text(0.1,0.5,'未收到','FontSize',11);
        end
    end
    sgtitle(sprintf('P5 端到端: %dx%d @Q%d, %s, Eb/N0=%d dB, 频偏 %d Hz', ...
            CFG.w, CFG.h, CFG.q, CFG.kind, CFG.EbN0dB, CFG.freqOffset), 'FontSize',11);
    if ~isfolder('plots'), mkdir('plots'); end
    saveas(f, fullfile('plots','p5_e2e_video.png'));
    fprintf('\n[OK] 端到端对比图已保存 plots/p5_e2e_video.png\n');
end

fprintf('\n################################################################\n');
fprintf('#   P5 完成                                                     #\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function p = psnr8(a, b)
    a = double(a); b = double(b);
    if ~isequal(size(a), size(b)), p = NaN; return; end
    mse = mean((a(:)-b(:)).^2);
    if mse == 0, p = Inf; else, p = 10*log10(255^2/mse); end
end

function s = pick(c, a, b)
    if c, s = a; else, s = b; end
end
