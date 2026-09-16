function e4_compare()
%E4_COMPARE  三组连接方案横向对比 —— 生成对比图与结论表 (纯 MATLAB)
%
%   读取 results/e4/{coax,short,long}/ 下各业务【最新一份】.mat, 汇总关键指标,
%   打印结论表并输出对比图。
%
%   输出:
%     plots/e4/_compare.png   三组横向对比图 (4 子图)
%     plots/e4/_compare.txt   结论表 (纯文本, 可直接贴进报告)
%
%   用法 (项目根目录):  e4_compare
%
%   ★ 注意: 三组的图片业务可能选中了不同分辨率/质量 (脚本按"PSNR最高且单帧可传"选),
%           故 PSNR 不宜直接横向比较 —— 图中会标注各自的配置。

    links = {'coax', 'short', 'long'};
    lname = {'同轴线', '短天线 5cm', '长天线 10cm'};
    bizs  = {'text', 'image', 'audio', 'video'};
    nL = numel(links);

    %% ===== 1. 收集各业务最新数据 =====
    D = cell(nL, numel(bizs));
    for i = 1:nL
        for j = 1:numel(bizs)
            d  = fullfile('results', 'e4', links{i});
            fs = dir(fullfile(d, sprintf('%s_%s_*.mat', links{i}, bizs{j})));
            if isempty(fs), continue; end
            [~, k] = max([fs.datenum]);
            try
                D{i,j} = load(fullfile(fs(k).folder, fs(k).name), 'cfg', 'metrics');
            catch ME
                fprintf(2, '  [!] 读取 %s/%s 失败: %s\n', links{i}, bizs{j}, ME.message);
            end
        end
    end

    %% ===== 2. 提取指标 =====
    % 物理量
    pwr  = nan(nL, numel(bizs));   % 接收功率 dBFS
    fEst = nan(nL, 1);
    % 业务质量
    txtOK = nan(nL,1);   txtByte = nan(nL,1);
    imgPSNR = nan(nL,1); imgRes = cell(nL,1);
    audRho = nan(nL,1);  audSNR = nan(nL,1);
    vidFrame = nan(nL,1); vidPSNR = nan(nL,1); vidFPS = nan(nL,1);

    for i = 1:nL
        for j = 1:numel(bizs)
            M = D{i,j};
            if isempty(M), continue; end
            m = M.metrics;
            if isfield(m,'rxPowerDbfs'), pwr(i,j) = m.rxPowerDbfs; end
            switch bizs{j}
                case 'text'
                    if isfield(m,'charOK'),  txtOK(i)   = double(m.charOK); end
                    if isfield(m,'byteOK'),  txtByte(i) = double(m.byteOK)*100; end
                    if isfield(m,'freqEstMean'), fEst(i) = m.freqEstMean; end
                case 'image'
                    if isfield(m,'psnr'), imgPSNR(i) = m.psnr; end
                    if isfield(m,'W'), imgRes{i} = sprintf('%dx%d Q%d', m.W, m.H, m.q); end
                case 'audio'
                    if isfield(m,'rho'),    audRho(i) = m.rho; end
                    if isfield(m,'segSNR'), audSNR(i) = m.segSNR; end
                case 'video'
                    if isfield(m,'frameOK'),  vidFrame(i) = m.frameOK*100; end
                    if isfield(m,'psnrMean'), vidPSNR(i)  = m.psnrMean; end
                    if isfield(m,'fps'),      vidFPS(i)   = m.fps; end
            end
        end
    end

    %% ===== 3. 标定结果 (链路损耗) =====
    calGain = nan(nL,1); calPwr = nan(nL,1);
    for i = 1:nL
        fs = dir(fullfile('results','e4','antenna', sprintf('ant_calib_%s_*.mat', links{i})));
        if isempty(fs), continue; end
        [~, k] = max([fs.datenum]);
        try
            M = load(fullfile(fs(k).folder, fs(k).name), 'metrics');
            calGain(i) = double(M.metrics.rxGainBest);
            calPwr(i)  = double(M.metrics.pwrBest);
        catch
        end
    end

    %% ===== 4. 打印结论表 =====
    fprintf('\n');
    fprintf('==================================================================\n');
    fprintf('  E4 三组连接方案对比\n');
    fprintf('==================================================================\n');
    fprintf('%-14s %10s %13s\n', '链路', '标定RxGain', '接收功率');
    fprintf('%s\n', repmat('-', 1, 40));
    for i = 1:nL
        fprintf('%-14s %8.0f dB %10.2f dBFS\n', lname{i}, calGain(i), calPwr(i));
    end
    fprintf('%s\n', repmat('-', 1, 40));
    dGain = calGain(2) - calGain(1);
    dPwr  = calPwr(2)  - calPwr(1);
    fprintf('天线组比同轴组多需 %.0f dB 增益, 接收功率仅差 %.1f dB\n', dGain, dPwr);
    fprintf('⇒ 天线路径耦合损耗 ≈ %.0f dB\n', dGain - abs(dPwr));
    fprintf('长/短天线 (同为 %.0f dB): 功率差 %+.2f dB\n', calGain(2), calPwr(3)-calPwr(2));

    fprintf('\n%-14s %10s %10s %12s %12s\n', '链路', '文本一致', '图片PSNR', '音频相关', '视频帧完成');
    fprintf('%s\n', repmat('-', 1, 62));
    for i = 1:nL
        fprintf('%-14s %10.0f %10.2f %12.4f %11.0f%%\n', ...
            lname{i}, txtOK(i), imgPSNR(i), audRho(i), vidFrame(i));
    end
    fprintf('%s\n', repmat('-', 1, 62));
    fprintf('★ 图片配置: ');
    for i = 1:nL
        fprintf('%s=%s  ', links{i}, imgRes{i});
    end
    fprintf('\n  (配置不同, PSNR 不宜直接横向比较)\n');

    %% ===== 5. 出对比图 =====
    C1 = [0.12 0.37 0.75]; C2 = [0.07 0.63 0.55]; C3 = [0.72 0.45 0.10];
    cols = [C1; C2; C3];

    fig = figure('Position', [60 60 1000 720], 'Color', 'w', 'Visible', 'on');
    x = 1:nL;

    % ① 链路损耗: 标定 RxGain
    ax1 = subplot(2,2,1);
    b = bar(ax1, x, calGain, 0.55, 'FaceColor', 'flat');
    b.CData = cols;
    hold(ax1, 'on');
    for i = 1:nL
        text(ax1, i, calGain(i)+1, sprintf('%.0f dB', calGain(i)), ...
             'HorizontalAlignment','center', 'FontSize', 9);
    end
    set(ax1, 'XTick', x, 'XTickLabel', lname, 'FontSize', 9);
    ylabel(ax1, '标定 RxGain (dB)'); grid(ax1, 'on'); set(ax1, 'GridAlpha', 0.2);
    title(ax1, '① 达到相同接收功率所需的接收增益', 'FontSize', 11);

    % ② 接收功率
    ax2 = subplot(2,2,2);
    b2 = bar(ax2, x, mean(pwr, 2, 'omitnan'), 0.55, 'FaceColor', 'flat');
    b2.CData = cols;
    hold(ax2, 'on');
    yline(ax2, -20, '--', '上限 -20', 'Color', [0.85 0.25 0.25]);
    yline(ax2, -30, '--', '下限 -30', 'Color', [0.85 0.25 0.25]);
    set(ax2, 'XTick', x, 'XTickLabel', lname, 'FontSize', 9);
    ylabel(ax2, '接收功率 (dBFS)'); grid(ax2, 'on'); set(ax2, 'GridAlpha', 0.2);
    title(ax2, '② 接收功率 (四业务平均, 目标带内)', 'FontSize', 11);

    % ③ 业务质量 (归一化便于同图)
    ax3 = subplot(2,2,3);
    Q = [txtByte/100, imgPSNR/40, audRho, vidFrame/100];   % 归一化到 0~1
    b3 = bar(ax3, x, Q, 0.8);
    set(ax3, 'XTick', x, 'XTickLabel', lname, 'FontSize', 9);
    ylabel(ax3, '归一化指标 (1.0 = 理想)'); ylim(ax3, [0 1.15]);
    grid(ax3, 'on'); set(ax3, 'GridAlpha', 0.2);
    legend(ax3, {'文本正确率','图片PSNR/40dB','音频相关','视频帧完成率'}, ...
           'Location', 'southoutside', 'Orientation', 'horizontal', 'FontSize', 8);
    title(ax3, '③ 业务质量横向对比', 'FontSize', 11);

    % ④ 音频 & 视频细节
    ax4 = subplot(2,2,4);
    yyaxis(ax4, 'left');
    plot(ax4, x, audSNR, '-o', 'Color', C2, 'LineWidth', 1.5, 'MarkerFaceColor', C2);
    ylabel(ax4, '音频分段 SNR (dB)');
    yyaxis(ax4, 'right');
    plot(ax4, x, vidPSNR, '-s', 'Color', C3, 'LineWidth', 1.5, 'MarkerFaceColor', C3);
    ylabel(ax4, '视频 PSNR (dB)');
    set(ax4, 'XTick', x, 'XTickLabel', lname, 'FontSize', 9);
    grid(ax4, 'on'); set(ax4, 'GridAlpha', 0.2);
    title(ax4, '④ 音频 / 视频 质量细节', 'FontSize', 11);

    sgtitle('E4 三组连接方案 (同轴 / 短天线 / 长天线) 横向对比', 'FontSize', 12.5);

    if ~isfolder(fullfile('plots','e4')), mkdir(fullfile('plots','e4')); end
    try
        exportgraphics(fig, fullfile('plots','e4','_compare.png'), 'Resolution', 130);
    catch
        saveas(fig, fullfile('plots','e4','_compare.png'));
    end
    fprintf('\n[OK] 对比图已保存: plots/e4/_compare.png\n');

    %% ===== 6. 结论表写盘 =====
    lines = {};
    lines{end+1} = 'E4 三组连接方案对比';
    lines{end+1} = sprintf('生成时间: %s', datestr(now));
    lines{end+1} = '';
    lines{end+1} = sprintf('%-14s %12s %14s', '链路', '标定RxGain', '接收功率(dBFS)');
    for i = 1:nL
        lines{end+1} = sprintf('%-14s %10.0f dB %12.2f', lname{i}, calGain(i), calPwr(i));
    end
    lines{end+1} = '';
    lines{end+1} = sprintf('天线 vs 同轴: 多需 %.0f dB 增益, 功率差 %.1f dB => 耦合损耗约 %.0f dB', ...
                           dGain, dPwr, dGain-abs(dPwr));
    lines{end+1} = sprintf('长 vs 短天线: 功率差 %+.2f dB', calPwr(3)-calPwr(2));
    lines{end+1} = '';
    lines{end+1} = sprintf('%-14s %10s %10s %12s %12s', '链路','文本一致','图片PSNR','音频相关','视频帧完成%');
    for i = 1:nL
        lines{end+1} = sprintf('%-14s %10.0f %10.2f %12.4f %12.0f', ...
            lname{i}, txtOK(i), imgPSNR(i), audRho(i), vidFrame(i));
    end
    fid = fopen(fullfile('plots','e4','_compare.txt'), 'w', 'n', 'UTF-8');
    if fid > 0
        fwrite(fid, unicode2native(strjoin(lines, newline), 'UTF-8'), 'uint8');
        fclose(fid);
        fprintf('[OK] 结论表已保存: plots/e4/_compare.txt\n');
    end
    fprintf('==================================================================\n\n');
end
