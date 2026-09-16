%% main_p2_loopback.m
% P2 视频编解码链路验证 —— 纯软件回环 (不经射频)
%
% 验证内容:
%   T1 单帧闭环: 编码 -> 分片 -> 重组 -> 解码, 要求【比特级完全一致】
%   T2 压缩率随内容复杂度变化 (simple / complex / moving)
%   T3 重组器鲁棒性: 丢片 / 重复片 / 乱序 / 帧号跳变
%   T4 视频流吞吐与帧率实测 (纯软件, 无射频)
%
% 用法: matlab -batch "addpath('video'); main_p2_loopback"

clear; clc; close all;
addpath('video');
P = video_protocol();

fprintf('\n################################################################\n');
fprintf('#   P2  视频编解码链路验证 (纯软件回环)                         #\n');
fprintf('################################################################\n');
fprintf('协议: 载荷 %d B = 分片头 %d B + 数据 %d B, 上限 %d 片/帧\n\n', ...
        P.PayloadBytes, P.HeaderBytes, P.DataBytes, P.MaxSlices);

%% ===== T1 单帧闭环 (比特级一致性) =====
fprintf('===== T1 单帧闭环 =====\n');
img = video_testframe(240, 320, 'moving', 1);
fprintf('测试帧 %dx%d\n', size(img,1), size(img,2));

% 预热 (消除 JIT/文件系统冷启动, 否则首次计时会虚高约 40 倍)
for i = 1:5, jb = jpeg_encode(img, 50); jpeg_decode(jb); end

NREP = 20;
t0 = tic; for i = 1:NREP, jb = jpeg_encode(img, 50); end; tEnc = toc(t0)/NREP*1000;
fprintf('  JPEG 编码      : %5d 字节, %.2f ms (热身 %d 次后平均)\n', numel(jb), tEnc, NREP);

[pl, info] = video_slicer(jb, 1);
fprintf('  分片           : %d 片 (开销 %.2f%%), 载荷矩阵 %dx%d\n', ...
        info.totalSlices, info.overheadRatio*100, size(pl,1), size(pl,2));

% 完美回环: 逐片推入重组器
st = video_reassembler();
got = [];
for i = 1:size(pl,2)
    [st, done, b] = video_reassembler(st, pl(:,i));
    if done, got = b; end
end
okBytes = isequal(got, jb);
fprintf('  重组           : 收齐=%d, 字节级一致=%d (%d 字节)\n', ...
        st.nFramesOK, okBytes, numel(got));

t0 = tic; for i = 1:NREP, img2 = jpeg_decode(got); end; tDec = toc(t0)/NREP*1000;
fprintf('  JPEG 解码      : %.2f ms\n', tDec);
fprintf('  图像 PSNR      : %.2f dB\n', psnr8(img, img2));
fprintf('  判定           : %s\n\n', tf(okBytes && isequal(size(img),size(img2))));

%% ===== T2 压缩率随内容复杂度变化 =====
fprintf('===== T2 压缩率 vs 内容复杂度 (320x240, Q=50) =====\n');
kinds = {'simple','complex','moving'};
fprintf('%10s | %10s | %12s | %14s | %10s\n', '内容类型','字节/帧','分片数','可达帧率*','PSNR(dB)');
fprintf('%s\n', repmat('-',1,66));
RAW = 320*240;                      % 未压缩字节数
VNET = 49875;                       % 链路视频净荷字节/s (399 kbps)
for i = 1:numel(kinds)
    im = video_testframe(240, 320, kinds{i}, 5);
    t0 = tic; jb2 = jpeg_encode(im, 50); te = toc(t0)*1000;
    [~, inf2] = video_slicer(jb2, 1);
    im2 = jpeg_decode(jb2);
    % 可达帧率需把分片头开销算进去
    effBytes = numel(jb2) * (P.PayloadBytes / P.DataBytes);
    fprintf('%10s | %10d | %12d | %13.1f | %8.2f\n', ...
            kinds{i}, numel(jb2), inf2.totalSlices, VNET/effBytes, psnr8(im, im2));
end
fprintf('  * 可达帧率已计入分片头开销 (x%.3f)\n\n', P.PayloadBytes/P.DataBytes);

%% ===== T3 重组器鲁棒性 =====
fprintf('===== T3 重组器鲁棒性 =====\n');
jb = jpeg_encode(video_testframe(240,320,'moving',7), 50);
[pl, info] = video_slicer(jb, 7);
N = info.totalSlices;

% T3-a 丢中间一片
st = video_reassembler(); gotDrop = [];
for i = 1:N
    if i == ceil(N/2), continue; end
    [st, done, b] = video_reassembler(st, pl(:,i));
    if done, gotDrop = b; end
end
fprintf('  T3-a 丢中间1片      : 输出帧=%d (应为0), 收齐=%d, 累计片=%d/%d\n', ...
        ~isempty(gotDrop), st.nFramesOK, st.nRecv, N);

% T3-b 整帧丢失 (帧号跳变) —— 真实链路中"整帧丢失"表现为下一帧号直接到来
st = video_reassembler(); gotDrop2 = [];
for i = 1:N-1                                  % 帧7 只到 N-1 片
    [st, ~, ~] = video_reassembler(st, pl(:,i));
end
pl8 = video_slicer(jb, 8);                     % 帧8 到来 => 应判定帧7丢失
for i = 1:size(pl8,2)
    [st, done, b] = video_reassembler(st, pl8(:,i));
    if done, gotDrop2 = b; end
end
fprintf('  T3-b 整帧7丢失      : 丢帧计数=%d (应为1), 帧8正常收齐=%d\n', ...
        st.nFramesDrop, isequal(gotDrop2, jb));

% T3-b2 帧内部分片丢失后直接跳到下一帧 (最常见的真实丢包模式)
st = video_reassembler();
for i = 1:round(N/3)
    [st, ~, ~] = video_reassembler(st, pl(:,i));   % 只收到前 1/3 片
end
[st, ~, ~] = video_reassembler(st, pl8(:,1));      % 直接跳到帧8
fprintf('  T3-b2 帧内部分丢+跳变: 丢帧计数=%d (应为1)\n', st.nFramesDrop);

% T3-c 重复片
st = video_reassembler(); gotDup = [];
[st,~,~] = video_reassembler(st, pl(:,1));
[st,~,~] = video_reassembler(st, pl(:,1));        % 重复
for i = 2:N
    [st, done, b] = video_reassembler(st, pl(:,i));
    if done, gotDup = b; end
end
fprintf('  T3-c 第1片重复      : 重复计数=%d, 收齐=%d, 字节一致=%d\n', ...
        st.nSlicesDup, st.nFramesOK, isequal(gotDup, jb));

% T3-d 乱序
st = video_reassembler(); gotPerm = [];
perm = randperm(N);
for i = perm
    [st, done, b] = video_reassembler(st, pl(:,i));
    if done, gotPerm = b; end
end
fprintf('  T3-d 完全乱序       : 收齐=%d, 字节一致=%d\n', st.nFramesOK, isequal(gotPerm, jb));

% T3-e 正常
st = video_reassembler(); okAll = 0;
for i = 1:N
    [st, done, b] = video_reassembler(st, pl(:,i));
    if done, okAll = isequal(b, jb); end
end
fprintf('  T3-e 正常顺序       : 字节一致=%d\n\n', okAll);

%% ===== T4 视频流吞吐实测 (纯软件) =====
fprintf('===== T4 视频流吞吐实测 (纯软件回环, 30 帧) =====\n');
fprintf('%10s | %12s | %14s | %14s\n', '内容类型','平均字节/帧','平均分片数','软环回帧率');
fprintf('%s\n', repmat('-',1,60));
NF = 30;
for i = 1:numel(kinds)
    st = video_reassembler();
    totBytes = 0; nOK = 0;
    t0 = tic;
    for k = 1:NF
        im = video_testframe(240, 320, kinds{i}, k);
        jb = jpeg_encode(im, 50);
        [pl, inf2] = video_slicer(jb, mod(k,256));
        totBytes = totBytes + numel(jb);
        for j = 1:size(pl,2)
            [st, done, b] = video_reassembler(st, pl(:,j));
            if done
                im2 = jpeg_decode(b);   %#ok<NASGU>  (真实链路中用于显示)
                nOK = nOK + 1;
            end
        end
    end
    dt = toc(t0);
    fprintf('%10s | %12.0f | %14.1f | %11.1f fps\n', ...
            kinds{i}, totBytes/NF, totBytes/NF/P.DataBytes, nOK/dt);
end

fprintf('\n################################################################\n');
fprintf('#   P2 完成                                                     #\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function p = psnr8(a, b)
    a = double(a); b = double(b);
    if ~isequal(size(a), size(b)), p = NaN; return; end
    mse = mean((a(:)-b(:)).^2);
    if mse == 0, p = Inf; else, p = 10*log10(255^2/mse); end
end

function s = tf(b)
    if b, s = '通过 [PASS]'; else, s = '未通过 [FAIL]'; end
end
