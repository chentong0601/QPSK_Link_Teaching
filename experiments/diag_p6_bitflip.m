%experiments/diag_p6_bitflip.m  P6b PSNR 17dB 归因诊断
%  假设: 真实空口存在少量 payload 位错误 (帧头 8-bit 校验不保护 payload),
%        JPEG 结构仍完整但 DCT 系数被扰动 -> 图像"对比度降低"式损伤
%  方法: 在已知图像上人为注入分级位错误, 测量 PSNR, 反推空口误码量级
%  用法: matlab -batch "addpath('experiments'); diag_p6_bitflip"

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync'); addpath('video');
params = init_params;
P = video_protocol();

img = imresize(video_testframe(240, 320, 'moving', 1), [144 176]);
jb  = jpeg_encode(img, 50);
fprintf('图像 176x144 @Q50 -> JPEG %d 字节, 分 %d 片\n', numel(jb), ceil(numel(jb)/58));

% 基准 (无损)
img0 = jpeg_decode(jb);
fprintf('\n===== 位错误敏感度 (每点 15 次随机位置) =====\n');
fprintf('  错误位数 |  PSNR均值 |  PSNR最小 |  PSNR最大\n');

nBit = size(jb,1)*8;
rates = [0 1 2 4 8 16 32 64];
for r = rates
    psnrs = [];
    for trial = 1:15
        rng(1000 + trial*13 + r);
        bad = jb;
        if r > 0
            % 随机选 r 个 bit 位置翻转
            pos = randperm(nBit, min(r, nBit));
            for p = pos
                byteIdx = floor((p-1)/8) + 1;
                bitIdx  = mod(p-1, 8);
                bad(byteIdx) = bitxor(bad(byteIdx), uint8(2^bitIdx));
            end
        end
        try
            im = jpeg_decode(bad);
            if isequal(size(im), size(img))
                psnrs(end+1) = psnrLocal(img, im); %#ok<AGROW>
            end
        catch
            % 码流损坏 -> 视为完全失败
        end
    end
    if isempty(psnrs)
        fprintf('  %6d   |   (全部解码失败)\n', r);
    else
        fprintf('  %6d   |  %7.2f  |  %7.2f  |  %7.2f   (成功 %d/15)\n', ...
                r, mean(psnrs), min(psnrs), max(psnrs), numel(psnrs));
    end
end

% 参考: 无错时的 JPEG 本底
fprintf('\nJPEG 本底 (Q50 无损回环): %.2f dB\n', psnrLocal(img, img0));
fprintf('空口实测: 17.07 dB\n');

%% ---- 附加: 码流"整体偏移"假设 (若某片丢失/错序, 字节流会整体移位) ----
fprintf('\n===== 码流移位假设 (少/多 1~3 字节 -> 后续全部错位) =====\n');
for sh = [-3 -2 -1 1 2 3]
    if sh > 0, bad = [jb(sh+1:end); zeros(sh,1,'uint8')];
    else,      bad = [zeros(-sh,1,'uint8'); jb(1:end+sh)]; end
    try
        im = jpeg_decode(bad);
        if isequal(size(im), size(img))
            fprintf('  移位 %+d 字节 -> PSNR %.2f dB\n', sh, psnrLocal(img, im));
        else
            fprintf('  移位 %+d 字节 -> 尺寸变化 %s\n', sh, mat2str(size(im)));
        end
    catch
        fprintf('  移位 %+d 字节 -> 解码失败\n', sh);
    end
end

function p = psnrLocal(a, b)
    a = double(a); b = double(b);
    if ~isequal(size(a), size(b)), p = NaN; return; end
    mse = mean((a(:)-b(:)).^2);
    if mse == 0, p = Inf; else, p = 10*log10(255^2/mse); end
end