%% ===== W4: 多内容源仿真验证 (文字 / 遥测 / 图像) =====
% 目的: 验证 content_encode/decode + 多帧传输 + 接收还原 的完整流程
%       仿真加 AWGN, 逐帧传输, 接收端按帧号收集后重建内容
% 用法: matlab -batch "main_w4_content"

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M=params.M; bp=params.bitsPerSym; L=params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

% 信道参数
EbN0dB = 12; EbN0 = 10^(EbN0dB/10);
Eg = sum(rrc.^2);

%% ================= 1. 文字消息 =================
fprintf('\n########## 文字消息 ##########\n');
% 注: -batch 模式对中文编码支持差, 这里用 ASCII 验证;
%     中文消息在 MATLAB GUI 里可正常收发 (GUI 环境编码完整)
msg = 'HELLO QPSK! LOW-ALTITUDE LINK TEST';
[frames, meta] = content_encode('text', params, msg);
recvFrames = transmit_frames_sim(frames, params, rrc, scrambler, EbN0, Eg);
recvText = content_decode('text', recvFrames, meta);
fprintf('发送: "%s"\n接收: "%s"\n', msg, recvText);
fprintf('结果: %s\n', ternary(strcmp(recvText,msg), '[PASS]', '[FAIL]'));

%% ================= 2. 遥测数据帧 =================
fprintf('\n########## 遥测数据帧 ##########\n');
[frames, meta] = content_encode('telemetry', params);
recvFrames = transmit_frames_sim(frames, params, rrc, scrambler, EbN0, Eg);
tm = content_decode('telemetry', recvFrames, meta);
fprintf('还原遥测:\n');
fprintf('  高度=%.1f m, 速度=%.1f m/s\n', tm.altitude, tm.speed);
fprintf('  俯仰=%.1f 度, 横滚=%.1f 度, 偏航=%.1f 度\n', tm.pitch, tm.roll, tm.yaw);
fprintf('  电量=%d%%, 卫星=%d, 模式=%s\n', tm.battery, tm.sats, tm.mode);
ok = abs(tm.altitude-meta.tm.altitude)<0.01 && strcmp(tm.mode, meta.tm.mode);
fprintf('结果: %s\n', ternary(ok, '[PASS]', '[FAIL]'));

%% ================= 3. 图像传输 =================
fprintf('\n########## 图像传输 ##########\n');
% 生成合成测试图 (32x32, 含渐变+方块, 不依赖图像工具箱)
img = make_test_image(32);
[frames, meta] = content_encode('image', params, img);
fprintf('图像 %dx%d = %d 字节, 分 %d 帧传输\n', ...
    meta.imgSize(1), meta.imgSize(2), meta.totalBytes, meta.nFrames);
recvFrames = transmit_frames_sim(frames, params, rrc, scrambler, EbN0, Eg);
imgRecv = content_decode('image', recvFrames, meta);

% 计算误像素率
perr = mean(imgRecv(:) ~= img(:));
fprintf('像素错误率 = %.2f%%\n', 100*perr);
fprintf('结果: %s\n', ternary(perr<0.01, '[PASS]', '[FAIL]'));

% 显示原图 vs 还原图
figure('Position',[80 80 700 350],'Color','w');
subplot(1,2,1); imagesc(img); colormap(gray); axis equal off; title('发送图像');
subplot(1,2,2); imagesc(imgRecv); colormap(gray); axis equal off; title('接收还原');
if ~isfolder('plots'); mkdir('plots'); end
saveas(gcf,'plots/w4_image_transfer.png');
fprintf('图已保存: plots/w4_image_transfer.png\n');

%% ===== 局部函数 =====
function recvFrames = transmit_frames_sim(frames, params, rrc, scrambler, EbN0, Eg)
% 逐帧仿真传输: 组帧→成形→加噪→接收→解出payload
% 用帧号排序 (体现帧号的实际作用: 应对乱序/丢帧场景)
    L = params.SamplesPerSym; bp = params.bitsPerSym;
    sigma = sqrt(1*Eg/(2*EbN0*bp));
    n = length(frames);
    recvFrames = cell(n,1);
    recvNums   = zeros(n,1);
    for i = 1:n
        fSym = tx_frame(frames{i}, params, 0, i-1);   % 帧号 = i-1
        [tw, ~] = tx_baseband(fSym, L, rrc);
        tw = tw * 0.9/max(abs(tw));
        pad = 200;
        rw = [sigma*(randn(pad,1)+1j*randn(pad,1)); tw; sigma*(randn(pad,1)+1j*randn(pad,1))];
        rw = rw + sigma*(randn(size(rw))+1j*randn(size(rw)));
        [pb, hdr, ~] = rx_frame(rw, params, scrambler, rrc);
        recvFrames{i} = pb;
        recvNums(i)   = hdr.frameNum;
    end
    % 按帧号排序 (真实系统里帧可能乱序到达)
    [~, order] = sort(recvNums);
    recvFrames = recvFrames(order);
end

function img = make_test_image(n)
% 生成合成测试图: 对角渐变 + 中心方块 + 边缘边框
    [X,Y] = meshgrid(1:n,1:n);
    img = uint8(round(200 * (X+Y)/(2*n)));   % 渐变
    img(round(n/4):round(3*n/4), round(n/4):round(3*n/4)) = 250;  % 亮方块
    img(1:2,:) = 0; img(end-1:end,:) = 0;     % 边框
    img(:,1:2) = 0; img(:,end-1:end) = 0;
end

function out = ternary(cond, a, b)
    if cond, out = a; else, out = b; end
end
