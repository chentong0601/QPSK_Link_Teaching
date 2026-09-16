%% main_e3_video_tradeoff.m
% E3 视频参数权衡实验 (方案 §6.3 核心实验)
%
% 动机: P2 发现【内容复杂度】是决定单帧字节数的首要因素 (2055 -> 14132 B, 差 7 倍)。
%       简单合成图下 320x240 可达 22.7 fps, 但复杂内容只有 3.3 fps -> 不达标。
%       必须找到在接近真实视频的内容下仍满足帧率目标的 (分辨率, 质量) 工作点。
%
% 产出: (分辨率 x 质量 x 内容) -> (字节/帧, 帧率, PSNR) 全表 + 推荐工作点 + 权衡曲线
% 用法: matlab -batch "addpath('video'); main_e3_video_tradeoff"

clear; clc; close all;
addpath('video');
P = video_protocol();

%% ---- 链路预算 (唯一真源, 与方案的参数表一致) ----
params = init_params_lite();
LineRate    = params.SymbolRate * params.bitsPerSym;         % 500 kbps
PayloadRate = LineRate * params.PayloadSym / params.FrameSym;% 419 kbps
VideoRate   = PayloadRate * P.DataBytes / P.PayloadBytes;    % 392 kbps
VNET        = VideoRate / 8;                                 % 字节/s

fprintf('\n################################################################\n');
fprintf('#   E3  视频参数权衡实验                                        #\n');
fprintf('################################################################\n');
fprintf('链路预算: 线路 %.0f kbps -> 载荷 %.0f kbps -> 视频净荷 %.0f kbps (%.0f B/s)\n', ...
        LineRate/1e3, PayloadRate/1e3, VideoRate/1e3, VNET);
fprintf('帧率 = %.0f / (单帧字节数 x %.4f)   [%.4f 为分片头开销]\n\n', ...
        VNET, P.PayloadBytes/P.DataBytes, P.PayloadBytes/P.DataBytes);

%% ---- 扫描网格 ----
resList = [120 160; 144 176; 240 320; 480 640];   % [h w]
qList   = [20 30 40 50 65];
kinds   = {'simple','moving','complex'};
FPS_TARGET = 5;      % G2 目标
PSNR_MIN   = 28;     % 可接受画质下限

%% ---- 主扫描 ----
fprintf('%-8s %10s | %6s | %10s | %10s | %8s | %s\n', ...
        '内容','分辨率','质量','字节/帧','分片数','帧率','PSNR');
fprintf('%s\n', repmat('-',1,76));
rec = struct('kind',{},'h',{},'w',{},'q',{},'bytes',{},'slices',{},'fps',{},'psnr',{});
for ci = 1:numel(kinds)
    for ri = 1:size(resList,1)
        h = resList(ri,1); w = resList(ri,2);
        base = video_testframe(240, 320, kinds{ci}, 7);
        if ~isequal([h w], [240 320])
            base = imresize(base, [h w]);
        end
        for qi = 1:numel(qList)
            q = qList(qi);
            jb = jpeg_encode(base, q);
            nb = numel(jb);
            eff = nb * P.PayloadBytes / P.DataBytes;      % 计入分片头
            fps = VNET / eff;
            try
                [~, inf2] = video_slicer(jb, 1);
                nsl = inf2.totalSlices;
                d = jpeg_decode(jb);
                ps = psnr8(base, d);
                overLimit = false;
            catch
                % 超出协议上限 (255 片) 或解码失败 => 该组合不可用
                nsl = NaN; ps = NaN; fps = NaN; overLimit = true;
            end
            if overLimit
                fprintf('%-8s %5dx%-4d | %6d | %10d | %10s | %7s | %6s | 超协议上限\n', ...
                        kinds{ci}, w, h, q, nb, '--', '--', '--');
            else
                fprintf('%-8s %5dx%-4d | %6d | %10d | %10d | %7.1f | %6.2f\n', ...
                        kinds{ci}, w, h, q, nb, nsl, fps, ps);
            end
            rec(end+1) = struct('kind',kinds{ci},'h',h,'w',w,'q',q, ...
                                'bytes',nb,'slices',nsl, ...
                                'fps',fps,'psnr',ps); %#ok<SAGROW>
        end
        fprintf('%s\n', repmat('.',1,76));
    end
end

%% ---- 推荐工作点 ----
fprintf('\n===== 推荐工作点 (帧率 >= %g fps 且 PSNR >= %g dB) =====\n', FPS_TARGET, PSNR_MIN);
fprintf('%10s | %12s | %6s | %10s | %8s | %8s\n','内容','分辨率','质量','字节/帧','帧率','PSNR');
fprintf('%s\n', repmat('-',1,70));
for ci = 1:numel(kinds)
    cand = [];
    for i = 1:numel(rec)
        if strcmp(rec(i).kind, kinds{ci}) && ~isnan(rec(i).fps) && rec(i).fps >= FPS_TARGET
            cand(end+1) = i; %#ok<SAGROW>
        end
    end
    if isempty(cand)
        fprintf('%10s | %s\n', kinds{ci}, '** 无满足条件的组合 -> 需降低目标或改进链路 **');
        continue;
    end
    % 选 PSNR 最高且达标的
    [~, k] = max([rec(cand).psnr]);
    b = rec(cand(k));
    fprintf('%10s | %5dx%-6d | %6d | %10d | %7.1f | %7.2f\n', ...
            kinds{ci}, b.w, b.h, b.q, b.bytes, b.fps, b.psnr);
end

%% ---- 权衡曲线图 ----
f = figure('Position',[100 100 820 500],'Color','w');
cols = {'#185FA5','#0F6E56','#993C1D'};
mk   = {'o','s','^'};
hold on;
hSc = gobjects(1,numel(kinds));
for ci = 1:numel(kinds)
    idx = find(strcmp({rec.kind}, kinds{ci}) & ~isnan([rec.fps]));
    xs = [rec(idx).fps]; ys = [rec(idx).psnr];
    [xs, so] = sort(xs); ys = ys(so);        % 按帧率排序, 折线才连贯
    plot(xs, ys, '-', 'Color', cols{ci}, 'LineWidth', 0.6, 'HandleVisibility','off');
    hSc(ci) = scatter(xs, ys, 46, 'Marker', mk{ci}, 'MarkerEdgeColor','none', ...
                      'MarkerFaceColor', cols{ci});
end
hx = xline(FPS_TARGET, '--', sprintf('目标 %g fps', FPS_TARGET), ...
      'Color','#A32D2D','LineWidth',1.5,'FontSize',10,'LabelOrientation','horizontal');
hy = yline(PSNR_MIN, ':', sprintf('画质下限 %g dB', PSNR_MIN), 'Color','#888780','FontSize',10);
hx.Annotation.LegendInformation.IconDisplayStyle = 'off';
hy.Annotation.LegendInformation.IconDisplayStyle = 'off';
set(gca,'XScale','log','FontSize',11);
grid on; box on;
xlabel('可达帧率 (fps, 对数轴)','FontSize',12);
ylabel('图像 PSNR (dB)','FontSize',12);
title('E3 视频参数权衡: 帧率 vs 画质 (按内容复杂度分组)','FontSize',12);
legend(hSc, kinds, 'Location','southwest','FontSize',11);
if ~isfolder('plots'), mkdir('plots'); end
saveas(f, fullfile('plots','e3_video_tradeoff.png'));
fprintf('\n[OK] 权衡曲线已保存 plots/e3_video_tradeoff.png\n');

fprintf('\n################################################################\n');
fprintf('#   E3 完成                                                     #\n');
fprintf('################################################################\n\n');

%% ================= 局部函数 =================
function p = psnr8(a, b)
    a = double(a); b = double(b);
    if ~isequal(size(a), size(b)), p = NaN; return; end
    mse = mean((a(:)-b(:)).^2);
    if mse == 0, p = Inf; else, p = 10*log10(255^2/mse); end
end

function p = init_params_lite()
% 只取链路预算需要的参数 (避免依赖工程其它目录)
    p.SymbolRate = 250e3;   % kSps
    p.bitsPerSym = 2;       % QPSK
    p.PreambleSym = 32;
    p.HeaderSym  = 16;
    p.PayloadSym = 248;
    p.FrameSym   = p.PreambleSym + p.HeaderSym + p.PayloadSym;   % 296
end
