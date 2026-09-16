%% main_p6_video_overair.m
% P6b  空口实时视频传输 —— 真实 SDR 上的端到端联调
%
%   ⚠️ 必须在 MATLAB GUI 中运行！
%      (-batch 模式下 Support Package 路径未注册, sdrtx/sdrrx 不可用)
%
%   前置: 先运行 main_p6_link_test.m 测出单传输帧成功率 p,
%         再用 slice_budget(p) 选定分辨率/质量, 填入下方 CFG。
%
%   硬件接法 (与 W3 相同):
%     Pluto 的 TX 口与 RX 口各接一根天线, 间距 ≥10 cm
%     或 TX/RX 之间用衰减器有线连接 (更稳定, 推荐首次联调)
%
%   设计说明 (为什么参数要"按实测 p 选"):
%     一个视频帧需要 N 个传输帧全部到齐, 故 视频帧完成率 = p^N。
%     例如 p=0.98 时, 47 片的视频帧只有 39% 能完成; 换成 24 片 (160x120) 可到 62%。
%
%   用法: 在 MATLAB GUI 中打开本文件, 按 F5 运行

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync'); addpath('video');

%% ===== 配置 (按 P6a 实测结果调整) =====
CFG.h = 144;  CFG.w = 176;      % 视频分辨率
CFG.q = 50;                     % JPEG 质量
CFG.nVideo = 20;                % 视频帧数 (循环播放)
CFG.kind = 'moving';            % 内容类型
CFG.nRep = 1;                   % 抓取几个发射周期 (增加可提高收全概率)
CFG.RxGain = 30;                % P6a 显示 30 dB 频偏最稳（σ=6.9 Hz）
CFG.TxGain = -20;
CFG.dryRun = false;             % ★ 首次使用建议先改 true 自检, 再改 false 接硬件
CFG.dryRunSNR = 12;             % dryRun 时的 Eb/N0 (dB)

params = init_params;
P = video_protocol();
L  = params.SamplesPerSym;
bp = params.bitsPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

fprintf('\n');
fprintf('################################################################\n');
fprintf('#   P6b  空口实时视频传输                                       #\n');
fprintf('################################################################\n');
fprintf('视频 %dx%d @Q%d, %d 帧, 内容 %s\n', CFG.w, CFG.h, CFG.q, CFG.nVideo, CFG.kind);
fprintf('中心频率 %.3f GHz  采样率 %.0f kHz  TxGain %d dB  RxGain %d dB\n', ...
        params.CenterFrequency/1e9, params.SampleRate/1e3, CFG.TxGain, CFG.RxGain);

%% ===== 1. 组帧 =====
fprintf('\n===== 1. 发射端组帧 =====\n');
txImgs = cell(1, CFG.nVideo);
segs = {};  nPhys = 0;
txPayloads = {};                % ★ 诊断: 记录每个传输帧的载荷 (供接收侧逐字节比对)
t0 = tic;
for k = 1:CFG.nVideo
    img = imresize(video_testframe(240, 320, CFG.kind, k), [CFG.h CFG.w]);
    txImgs{k} = img;
    jb = jpeg_encode(img, CFG.q);
    [pl, info] = video_slicer(jb, mod(k-1,256));
    for i = 1:size(pl,2)
        fS = tx_frame(pl(:,i), params, 0, mod(nPhys,256));
        [w, ~] = tx_baseband(fS, L, rrc);
        w = w * 0.9/max(abs(w));
        if isempty(segs), Es = L*mean(abs(w).^2); end
        segs{end+1} = [w; zeros(80,1)]; %#ok<AGROW>
        txPayloads{end+1} = pl(:,i); %#ok<AGROW>
        nPhys = nPhys + 1;
    end
end
wave = vertcat(segs{:});
txTime = toc(t0);
fprintf('  传输帧 %d 个, 波形 %d 采样 = %.3f s\n', nPhys, numel(wave), numel(wave)/params.SampleRate);
fprintf('  组帧耗时 %.2f s\n', txTime);

%% ===== 2. 硬件收发 =====
rxData = [];
tx = [];  rx = [];
if CFG.dryRun
    % ---------- 自检模式: 不接硬件, 用仿真信道 ----------
    fprintf('\n[DRY-RUN] 跳过硬件, 使用仿真信道 (Eb/N0 = %d dB, 频偏 320 Hz)\n', CFG.dryRunSNR);
    nn = (0:numel(wave)-1).';
    rw = wave .* exp(1j*2*pi*320*nn/params.SampleRate);
    sg = sqrt(Es/(2*10^(CFG.dryRunSNR/10)*bp));
    rw = rw + sg*(randn(size(rw)) + 1j*randn(size(rw)));
    rxData = repmat(rw, CFG.nRep, 1);
    rxData = rxData - mean(rxData);
else
    try
        tx = sdrtx('Pluto');
        tx.CenterFrequency    = params.CenterFrequency;
        tx.BasebandSampleRate = params.SampleRate;
        tx.Gain               = CFG.TxGain;
        tx.OutputDataType     = 'double';
        transmitRepeat(tx, wave);
        fprintf('\n[OK] 已开始循环发射\n');

        rx = sdrrx('Pluto');
        rx.CenterFrequency    = params.CenterFrequency;
        rx.BasebandSampleRate = params.SampleRate;
        rx.GainSource         = 'Manual';
        rx.Gain               = CFG.RxGain;
        rx.SamplesPerFrame    = 8192;
        rx.OutputDataType     = 'double';

        for i = 1:3, rx(); end              % 丢弃起始瞬态

        nBlk = ceil(numel(wave)*CFG.nRep / 8192);
        rxData = zeros(nBlk*8192, 1);
        fprintf('  抓取 %d 采样 (%.3f s) ...\n', numel(rxData), numel(rxData)/params.SampleRate);
        t0 = tic;
        for i = 1:nBlk
            rxData((i-1)*8192+1 : i*8192) = rx();
        end
        fprintf('  抓取完成, 用时 %.2f s\n', toc(t0));
        rxData = rxData - mean(rxData);
    catch e
        fprintf('\n[!!] 硬件操作失败: %s\n', e.message);
        fprintf('     排查: ① findPlutoRadio 是否能发现设备 ② 是否在 GUI 中运行\n');
        fprintf('           ③ Support Package 是否安装 ④ 天线是否接好\n');
    end
    try, if ~isempty(tx), release(tx); end, catch, end
    try, if ~isempty(rx), release(rx); end, catch, end
    fprintf('[OK] 已释放硬件\n');
end

if isempty(rxData)
    fprintf('\n[!!] 无接收数据, 退出\n');  return;
end

%% ===== 3. 物理层解码 =====
fprintf('\n===== 3. 物理层解码 =====\n');
t0 = tic;
[pbs, st] = rx_receiver(rxData, params, scrambler, rrc, nPhys*CFG.nRep);
fprintf('  解出传输帧 %d 个 (目标 %d), 耗时 %.2f s\n', numel(pbs), nPhys, toc(t0));
if ~isempty(st.freqEsts)
    fprintf('  频偏估计: 均值 %.1f Hz, 标准差 %.1f Hz\n', ...
            mean(st.freqEsts), std(st.freqEsts));
end

%% ===== 3.5 诊断: 载荷字节比对 (定位 PSNR 低之根因) =====
fprintf('\n----- 诊断: 接收载荷 vs 发射载荷 -----\n');
txMap = containers.Map('KeyType','double','ValueType','any');
for i = 1:numel(txPayloads)
    q = double(txPayloads{i});
    txMap(q(1)*256 + q(2)) = txPayloads{i};
end
nPayOK = 0; nPayBad = 0; nByteErr = 0; nBitErr = 0;
nHdrErrByte = 0; nDataErrByte = 0; nNoKey = 0;
seqNum = zeros(1, numel(pbs));
for i = 1:numel(pbs)
    a = pbs{i}(:);
    if numel(a) < 4, nNoKey = nNoKey + 1; continue; end
    seqNum(i) = double(a(1));
    key = double(a(1))*256 + double(a(2));
    if ~isKey(txMap, key), nNoKey = nNoKey + 1; continue; end
    b = txMap(key);
    if numel(a) == numel(b) && isequal(a, b)
        nPayOK = nPayOK + 1;
    else
        nPayBad = nPayBad + 1;
        nb = min(numel(a), numel(b));
        d = a(1:nb) ~= b(1:nb);
        nByteErr = nByteErr + sum(d);
        nHdrErrByte  = nHdrErrByte  + sum(d(1:min(4,nb)));
        nDataErrByte = nDataErrByte + sum(d(min(5,nb+1):end));
        x = dec2bin(a(1:nb), 8); y = dec2bin(b(1:nb), 8);
        nBitErr = nBitErr + sum(x(:) ~= y(:));
    end
end
fprintf('  ★ 载荷完全正确 : %d / %d (%.2f%%)\n', nPayOK, numel(pbs), nPayOK/max(numel(pbs),1)*100);
fprintf('    有误 %d | 序号未匹配 %d | 字节错 %d (头 %d / 数据 %d) | 比特错 %d\n', ...
        nPayBad, nNoKey, nByteErr, nHdrErrByte, nDataErrByte, nBitErr);
fprintf('    接收视频帧号序列(前25): [%s]\n', num2str(seqNum(1:min(25,end))));
nWrap = sum(diff(seqNum) < 0);
fprintf('    帧号回退(乱序/环绕)次数: %d (20帧应 <2, 仅周期环绕)\n', nWrap);

% 接收信号统计 (判断 ADC 饱和)
fprintf('  接收波形: max %.3f | rms %.3f | |x|>0.99 占比 %.2f%%\n', ...
        max(abs(rxData)), sqrt(mean(abs(rxData).^2)), mean(abs(rxData)>0.99)*100);

%% ===== 4. 视频层重组与解码 =====
fprintf('\n===== 4. 视频层重组 =====\n');
rst = video_reassembler();
got = {};  gotPSNR = [];  gotNum = [];  gotBytes = {};
for i = 1:numel(pbs)
    curNum = double(pbs{i}(1));              % ★ 本片所属视频帧号
    [rst, done, jb] = video_reassembler(rst, pbs{i});
    if done
        try
            img = jpeg_decode(jb);
            got{end+1} = img; %#ok<AGROW>
            gotNum(end+1) = curNum; %#ok<AGROW>
            gotBytes{end+1} = numel(jb); %#ok<AGROW>
            % ★ 用真实帧号定位参考图 (而非接收计数), 避免丢帧导致对比错位
            kRef = curNum + 1;
            if kRef >= 1 && kRef <= CFG.nVideo && isequal(size(img), size(txImgs{kRef}))
                gotPSNR(end+1) = psnrLocal(txImgs{kRef}, img); %#ok<AGROW>
            end
        catch
            % 码流不完整, 跳过
        end
    end
end
fprintf('  接收视频帧号: [%s]\n', num2str(gotNum));
if ~isempty(gotBytes)
    fprintf('  接收JPEG字节数: [%s]\n', num2str(cell2mat(gotBytes)));
end
if ~isempty(gotPSNR)
    kk = min(6, numel(gotPSNR));
    fprintf('  帧号->PSNR: ');
    for i = 1:kk, fprintf('F%d:%.1f  ', gotNum(i), gotPSNR(i)); end
    fprintf('\n');
end
fprintf('  完整视频帧: %d (发送 %d 帧, 抓取 %d 个周期)\n', numel(got), CFG.nVideo, CFG.nRep);
fprintf('  传输层统计: 收片 %d, 重复片 %d, 丢帧 %d\n', ...
        rst.nSlicesRecv, rst.nSlicesDup, rst.nFramesDrop);
if ~isempty(gotPSNR)
    fprintf('  视频帧 PSNR: 均值 %.2f dB (%d 帧可比对)\n', mean(gotPSNR), numel(gotPSNR));
end
pFrame = numel(got) / (CFG.nVideo*CFG.nRep);
fprintf('  ★ 视频帧完成率 = %.1f%%\n', pFrame*100);

%% ===== 5. 结果显示 =====
nShow = min(4, numel(got));
if nShow > 0
    f = figure('Position',[80 80 900 620],'Color','w');
    for i = 1:nShow
        kRef = gotNum(i) + 1;                % ★ 按实际接收帧号取参考图
        if kRef < 1 || kRef > CFG.nVideo, kRef = i; end
        subplot(nShow,2,2*i-1);
        imshow(txImgs{kRef}); title(sprintf('发送帧 %d', kRef),'FontSize',10);
        subplot(nShow,2,2*i);
        imshow(got{i});
        if i <= numel(gotPSNR)
            title(sprintf('空口接收帧号 %d (PSNR %.1f dB)', gotNum(i), gotPSNR(i)),'FontSize',10);
        else
            title(sprintf('空口接收帧号 %d', gotNum(i)),'FontSize',10);
        end
    end
    sgtitle(sprintf('P6b 空口视频传输: %dx%d @Q%d, RxGain=%d dB', ...
            CFG.w, CFG.h, CFG.q, CFG.RxGain), 'FontSize',11);
    if ~isfolder('plots'), mkdir('plots'); end
    saveas(f, fullfile('plots','p6_overair_video.png'));
    fprintf('\n[OK] 对比图已保存 plots/p6_overair_video.png\n');
else
    fprintf('\n[!!] 未收到任何完整视频帧。请检查:\n');
    fprintf('     ① 先跑 main_p6_link_test.m 确认单帧成功率 p\n');
    fprintf('     ② 若 p < 0.98, 用 slice_budget(p) 降分辨率/质量以减少片数\n');
    fprintf('     ③ 确认天线接好、间距合适、RxGain 合适\n');
end

% 保存数据 (含诊断变量, 供离线深挖; 文件名含关键配置, 不同配置不互覆盖)
if ~isfolder('results'), mkdir('results'); end
fn = sprintf('results/p6b_%dx%d_q%d_g%d_%s.mat', ...
        CFG.w, CFG.h, CFG.q, round(CFG.RxGain), datestr(now,'yyyymmdd_HHMMSS'));
save(fn, 'CFG', 'rst', 'pFrame', 'rxData', 'pbs', 'txPayloads', ...
     'gotNum', 'gotBytes', 'seqNum', '-v7.3');
fprintf('[OK] 数据已保存 %s (含 rxData/pbs, 可离线诊断)\n', fn);

fprintf('\n################################################################\n');
fprintf('#   P6b 完成                                                    #\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function p = psnrLocal(a, b)
    a = double(a); b = double(b);
    if ~isequal(size(a), size(b)), p = NaN; return; end
    mse = mean((a(:)-b(:)).^2);
    if mse == 0, p = Inf; else, p = 10*log10(255^2/mse); end
end
