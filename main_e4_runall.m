%% main_e4_runall.m
% E4 系列内容类传输实验 —— 一键运行 + 自动汇总
%
%   依次执行 文字 / 图片 / 音频 / 视频 四类内容实验, 并在结束后生成
%   **results/E4_RUNLOG.md** 运行记录 (含状态/耗时/关键指标/错误信息),
%   便于事后复盘与逐次对比 (例如"同轴线 vs 天线"两轮)。
%
%   用法(二选一):
%     matlab -batch "main_e4_runall"        % 命令行批处理
%     main_e4_runall                        % MATLAB 命令窗直接运行
%
%   产物:
%     results/E4_RUNLOG.md                  ★ 运行记录 (人可读, 也可被脚本解析)
%     plots/e4_image.png, e4_audio.png, e4_video.png
%     results/e4_text|e4_image|e4_audio|e4_video/
%
%   说明: 子脚本开头用 `if ~exist('E4_BATCH','var')` 判断是否清理工作区;
%         本脚本先设 E4_BATCH=1, 从而保护批处理的循环变量不被清掉。

clear; clc; close all;
E4_BATCH = 1;          % ★ 必须在 run() 之前设置

thisDir = fileparts(mfilename('fullpath'));
cd(thisDir);           % 保证相对路径 (content/ plots/ results/) 正确
addpath('experiments');

tasks = {'main_e4_text', 'main_e4_image', 'main_e4_audio', 'main_e4_video'};
names = {'文字', '图片', '音频', '视频'};
stat  = cell(numel(tasks), 4);      % {状态, 耗时, 指标, 错误信息}

tRun0 = tic;
fprintf('\n');
fprintf('################################################################\n');
fprintf('#      E4 系列 内容类传输实验 —— 一键运行                          #\n');
fprintf('################################################################\n');

for i = 1:numel(tasks)
    fprintf('\n\n>>>>>>>>>> [%d/%d]  %s 实验  <<<<<<<<<<\n', i, numel(tasks), names{i});
    E4_METRIC = '';                 % 每次清空, 防止读到上一轮残留
    t0 = tic;
    st = 'OK'; msg = '';
    try
        run(tasks{i});
    catch ME
        st  = 'FAIL';
        msg = ME.message;
        fprintf(2, '\n[FAIL] %s\n  %s\n', tasks{i}, ME.message);
    end
    dt = toc(t0);

    metric = '';
    if exist('E4_METRIC', 'var') && ischar(E4_METRIC)
        metric = E4_METRIC;
    end
    stat{i, 1} = st;
    stat{i, 2} = sprintf('%.1f s', dt);
    stat{i, 3} = metric;
    stat{i, 4} = msg;
end
totalDur = toc(tRun0);

%% ===== 汇总: 控制台 =====
fprintf('\n\n');
fprintf('################################################################\n');
fprintf('#      E4 系列 运行汇总                                            #\n');
fprintf('################################################################\n');
fprintf('%-8s %-7s %-9s %s\n', '实验', '状态', '耗时', '关键指标');
fprintf('%s\n', repmat('-', 1, 72));
for i = 1:numel(tasks)
    line = stat{i, 3};
    if strcmp(stat{i, 1}, 'FAIL'), line = ['(错误) ' stat{i, 4}]; end
    fprintf('%-8s %-7s %-9s %s\n', names{i}, stat{i, 1}, stat{i, 2}, line);
end
fprintf('%s\n', repmat('-', 1, 72));
fprintf('总耗时: %.1f s\n', totalDur);

%% ===== 汇总: 写盘 (results/E4_RUNLOG.md) =====
if ~isfolder('results'), mkdir('results'); end
logPath = fullfile('results', 'E4_RUNLOG.md');

lines = {};
lines{end+1} = '# E4 内容类传输实验 —— 运行记录';
lines{end+1} = '';
lines{end+1} = sprintf('- 运行时间: %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
lines{end+1} = sprintf('- 四类实验总耗时: %.1f s', totalDur);
lines{end+1} = '';
lines{end+1} = '> ⚠️ 本轮实验的信道为**仿真信道**（AWGN + 载波频偏），未接入 Pluto 硬件。';
lines{end+1} = '> 硬件在环结果请见 P6 / W3 / W5 等既有报告。';
lines{end+1} = '';
lines{end+1} = '| 实验 | 状态 | 耗时 | 关键指标 / 错误信息 |';
lines{end+1} = '|------|------|------|--------------------|';
for i = 1:numel(tasks)
    line = stat{i, 3};
    if strcmp(stat{i, 1}, 'FAIL')
        line = sprintf('❌ %s', stat{i, 4});
    elseif isempty(line)
        line = '(未产出指标)';
    end
    lines{end+1} = sprintf('| %s | %s | %s | %s |', names{i}, stat{i, 1}, stat{i, 2}, line);
end
lines{end+1} = '';
lines{end+1} = '## 产物清单';
lines{end+1} = '';
lines{end+1} = '| 类型 | 路径 |';
lines{end+1} = '|------|------|';
lines{end+1} = '| 文字 | `results/e4_text/e4_text.mat`, `rx_text.txt` |';
lines{end+1} = '| 图片 | `plots/e4_image.png`, `results/e4_image/{tx,rx}.png` |';
lines{end+1} = '| 音频 | `plots/e4_audio.png`, `results/e4_audio/{tx,rx}.wav` |';
lines{end+1} = '| 视频 | `plots/e4_video.png`, `results/e4_video/e4_video.mat` |';
lines{end+1} = '';
lines{end+1} = '## 素材';
lines{end+1} = '';
lines{end+1} = '- 文字: `content/text/*.txt`';
lines{end+1} = '- 图片: `content/image/*.jpg`';
lines{end+1} = '- 视频: `content/video/*.mp4`';
lines{end+1} = '- 音频: `content/audio/*.wav`';
lines{end+1} = '';

fid = fopen(logPath, 'w', 'n', 'UTF-8');
if fid > 0
    fwrite(fid, unicode2native(strjoin(lines, newline), 'UTF-8'), 'uint8');
    fclose(fid);
    fprintf('\n[OK] 运行记录已保存: %s\n', logPath);
else
    fprintf(2, '\n[!] 运行记录写入失败: %s\n', logPath);
end

fprintf('\n产物目录:\n');
fprintf('  记录: results/E4_RUNLOG.md   ← 每轮运行都会覆盖, 便于逐次对比\n');
fprintf('  图  : plots/e4/ 下的 <link>_text.png / _audio.png / _image.png / _video.png\n');
fprintf('  数据: results/e4/<link>/\n');
fprintf('  (四类业务图均由各业务脚本用 MATLAB 生成)\n');
fprintf('################################################################\n\n');
