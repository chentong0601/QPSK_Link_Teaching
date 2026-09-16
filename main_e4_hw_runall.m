function main_e4_hw_runall(link, rxGain, varargin)
%MAIN_E4_HW_RUNALL  E4 硬件在环一键运行 —— 指定链路, 依次跑 4 类业务
%
%   用法:
%     main_e4_hw_runall('coax')        % ① 同轴线直连
%     main_e4_hw_runall('short')       % ② 5 cm 短天线 ×2
%     main_e4_hw_runall('long')        % ③ 10 cm 长天线 ×2
%     main_e4_hw_runall('coax', 40)    % 可指定 RxGain (默认 30 dB)
%
%   可选实验条件 (键值对, 会写入 cfg 供报告溯源):
%     'antLenCm'  : 天线长度 cm   (默认: short=5, long=10, coax=NaN)
%     'antSepCm'  : 天线间距 cm   (默认: 天线组=3, 同轴=NaN)
%     'antOrient' : 天线朝向      (默认 'parallel'; 可选 'angled')
%   例: main_e4_hw_runall('short', rxGain, 'antSepCm', 6, 'antOrient', 'angled')
%
%   ⚠️ 必须在 MATLAB GUI 中运行!
%      (-batch 模式下 Support Package 路径未注册, sdrtx/sdrrx 不可用)
%
%   ★ 三组可比性提示:
%       不同天线的耦合损耗不同。若三组沿用同一 RxGain, 接收功率会不同,
%       则"天线差异"与"增益差异"会混在一起。**建议先用 e4_ant_calib 标定**,
%       使三组接收功率落在同一区间 (目标 -30 ~ -20 dBFS), 再正式采集。
%
%   产物: results/e4/<link>/<link>_<biz>_<时间戳>.mat
%         (每个 .mat 内含 cfg / metrics / raw 三变量)

    if nargin < 1 || isempty(link),   link   = 'coax'; end
    if nargin < 2 || isempty(rxGain), rxGain = 30;     end

    validLink = {'coax', 'short', 'long'};
    if ~ismember(link, validLink)
        error('link 必须是 %s 之一', strjoin(validLink, ' / '));
    end

    %% ===== 实验条件 (可选参数 + 按 link 的默认值) =====
    cond = struct('antLenCm', NaN, 'antSepCm', NaN, 'antOrient', 'parallel');
    for i = 1:2:numel(varargin)
        if i+1 <= numel(varargin)
            cond.(varargin{i}) = varargin{i+1};
        end
    end
    if isnan(cond.antLenCm)
        switch link
            case 'short', cond.antLenCm = 5;
            case 'long',  cond.antLenCm = 10;
        end
    end
    if isnan(cond.antSepCm) && ~strcmp(link, 'coax')
        cond.antSepCm = 3;          % Pluto TX/RX 接口间距 (固定, 约 3 cm)
    end

    thisDir = fileparts(mfilename('fullpath'));
    cd(thisDir);
    addpath('config'); addpath('transmitter'); addpath('receiver');
    addpath('sync'); addpath('video'); addpath('experiments');

    linkName = struct('coax', '同轴线直连', 'short', '5 cm 短天线 ×2', 'long', '10 cm 长天线 ×2');

    fprintf('\n');
    fprintf('################################################################\n');
    fprintf('#   E4 硬件在环 —— %s\n', linkName.(link));
    fprintf('#   RxGain = %d dB   (如需标定请先运行 e4_ant_calib)\n', rxGain);
    fprintf('################################################################\n');
    fprintf('\n⚠️  确认已接好: %s\n', linkName.(link));
    fprintf('    天线长度 %.0f cm | 间距 %.0f cm | 朝向 %s\n', ...
            cond.antLenCm, cond.antSepCm, cond.antOrient);
    fprintf('    接口间距约 3 cm (固定); 天线可旋转, 末端最大约 10 cm\n');
    fprintf('    Pluto TX 口 -> 发射侧, RX 口 -> 接收侧\n\n');
    fprintf('    ★ 如需修改实验条件, 用键值对参数重跑, 例如:\n');
    fprintf('      main_e4_hw_runall(''%s'', %d, ''antSepCm'', 6, ''antOrient'', ''angled'')\n\n', ...
            link, rxGain);
    input('    按回车开始运行 (Ctrl+C 取消) ...', 's');

    tasks = {'main_e4_text', 'main_e4_image', 'main_e4_audio', 'main_e4_video'};
    names = {'文字', '图片', '音频', '视频'};
    bizs  = {'text', 'image', 'audio', 'video'};
    stat  = cell(numel(tasks), 4);

    E4_FORCE_MODE   = 'hw';      % ★ 强制 4 个业务脚本走硬件模式
    E4_FORCE_LINK   = link;      % ★ 强制落盘到 results/e4/<link>/
    E4_FORCE_RXGAIN = rxGain;    % ★ 把标定得到的 RxGain 真正传给业务脚本
    E4_FORCE_TXGAIN = -20;       %   (此前遗漏! 业务脚本会退回硬编码默认值 30 dB)
    E4_FORCE_ANTLEN = cond.antLenCm;    % ★ 实验条件元数据 (写入 cfg)
    E4_FORCE_ANTSEP = cond.antSepCm;
    E4_FORCE_ANTORI = cond.antOrient;
    E4_BATCH        = 1;         % ★ 防子脚本 clear 掉本函数的变量

    tRun0 = tic;
    for i = 1:numel(tasks)
        fprintf('\n\n>>>>>>>>>> [%d/%d]  %s  <<<<<<<<<<\n', i, numel(tasks), names{i});
        E4_METRIC = '';
        t0 = tic;
        st = 'OK'; msg = '';
        try
            run(tasks{i});
        catch ME
            st  = 'FAIL';
            msg = ME.message;
            fprintf(2, '\n[FAIL] %s\n  %s\n', tasks{i}, ME.message);
        end
        stat{i, 1} = st;
        stat{i, 2} = sprintf('%.1f s', toc(t0));
        stat{i, 3} = '';
        if exist('E4_METRIC', 'var') && ischar(E4_METRIC) && ~isempty(E4_METRIC)
            stat{i, 3} = E4_METRIC;
        end
        stat{i, 4} = msg;

        % ★ 兜底: 脚本变量未传出时, 直接从最新 .mat 读取指标
        %   (图片业务曾出现"metrics 已存盘但 E4_METRIC 读不到", 根因未定位;
        %    此兜底不依赖变量传递, 从落盘数据反读, 保证汇总不缺项)
        if isempty(stat{i, 3}) && strcmp(st, 'OK')
            fb = e4_metric_from_mat(link, bizs{i});
            if ~isempty(fb)
                stat{i, 3} = fb;
                fprintf('    [兜底] 脚本未传出指标, 已从 .mat 读取: %s\n', fb);
            end
        end
    end
    totalDur = toc(tRun0);

    %% ===== 控制台汇总 =====
    fprintf('\n\n');
    fprintf('################################################################\n');
    fprintf('#   E4 硬件运行汇总 (%s)                                     \n', link);
    fprintf('################################################################\n');
    fprintf('%-6s %-6s %-9s %s\n', '业务', '状态', '耗时', '关键指标');
    fprintf('%s\n', repmat('-', 1, 70));
    for i = 1:numel(tasks)
        line = stat{i, 3};
        if strcmp(stat{i, 1}, 'FAIL'), line = ['(错误) ' stat{i, 4}]; end
        fprintf('%-6s %-6s %-9s %s\n', names{i}, stat{i, 1}, stat{i, 2}, line);
    end
    fprintf('%s\n', repmat('-', 1, 70));
    fprintf('总耗时: %.1f s\n', totalDur);

    %% ===== 写运行记录 (追加式, 保留各链路历史) =====
    if ~isfolder('results/e4'), mkdir('results/e4'); end
    logPath = fullfile('results', 'e4', 'E4_HW_RUNLOG.md');

    lines = {};
    if isfile(logPath)
        lines{end+1} = fileread(logPath);
        lines{end+1} = '';
    else
        lines{end+1} = '# E4 硬件在环 —— 运行记录';
        lines{end+1} = '';
        lines{end+1} = '> 三组连接方案的实测结果逐次追加于此, 便于横向对比。';
        lines{end+1} = '';
    end

    lines{end+1} = sprintf('## %s　%s　(RxGain %d dB)', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                           linkName.(link), rxGain);
    lines{end+1} = '';
    lines{end+1} = sprintf('- 总耗时 %.1f s', totalDur);
    lines{end+1} = '';
    lines{end+1} = '| 业务 | 状态 | 耗时 | 关键指标 |';
    lines{end+1} = '|------|------|------|---------|';
    for i = 1:numel(tasks)
        line = stat{i, 3};
        if strcmp(stat{i, 1}, 'FAIL'),    line = sprintf('❌ %s', stat{i, 4});
        elseif isempty(line),             line = '(未产出指标)'; end
        lines{end+1} = sprintf('| %s | %s | %s | %s |', names{i}, stat{i, 1}, stat{i, 2}, line);
    end
    lines{end+1} = '';

    fid = fopen(logPath, 'w', 'n', 'UTF-8');
    if fid > 0
        fwrite(fid, unicode2native(strjoin(lines, newline), 'UTF-8'), 'uint8');
        fclose(fid);
        fprintf('\n[OK] 运行记录已追加: %s\n', logPath);
    end

    fprintf('\n数据目录: results/e4/%s/\n', link);
    fprintf('图目录  : plots/e4/  (文字/音频/图片/视频对比图均由各业务脚本用 MATLAB 生成)\n');
    fprintf('下一步  : 换接法后再次调用 main_e4_hw_runall(''<下一组>'')\n');
    fprintf('################################################################\n\n');
end

function s = e4_metric_from_mat(link, biz)
%E4_METRIC_FROM_MAT  从最新的 <link>_<biz>_*.mat 提取关键指标摘要 (兜底用)
    s = '';
    d = fullfile('results', 'e4', link);
    if ~isfolder(d), return; end
    fs = dir(fullfile(d, sprintf('%s_%s_*.mat', link, biz)));
    if isempty(fs), return; end
    [~, i0] = max([fs.datenum]);
    try
        M = load(fullfile(fs(i0).folder, fs(i0).name), 'metrics');
    catch
        return;
    end
    if ~isfield(M, 'metrics'), return; end
    m = M.metrics;
    switch biz
        case 'text'
            s = sprintf('字节正确率 %.4f%% | 文本一致 %d | (来源: .mat)', ...
                getf(m,'byteOK',NaN)*100, getf(m,'charOK',0));
        case 'image'
            s = sprintf('扫描 %d 组 | 最优 %dx%d Q%d PSNR %.2f dB | 超限 %d 组 | (来源: .mat)', ...
                getf(m,'nScan',0), getf(m,'W',0), getf(m,'H',0), getf(m,'q',0), ...
                getf(m,'psnr',NaN), getf(m,'nOver',0));
        case 'audio'
            s = sprintf('波形相关 %.4f | 分段SNR %.2f dB | (来源: .mat)', ...
                getf(m,'rho',NaN), getf(m,'segSNR',NaN));
        case 'video'
            s = sprintf('帧 %.1f%% | PSNR %.2f dB | %.1f fps | (来源: .mat)', ...
                getf(m,'frameOK',NaN)*100, getf(m,'psnrMean',NaN), getf(m,'fps',NaN));
    end
end

function v = getf(m, f, dflt)
%GETF  安全取字段 (缺失则返回默认值)
    if isfield(m, f), v = double(m.(f)); else, v = dflt; end
end
