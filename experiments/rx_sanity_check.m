function report = rx_sanity_check(x, fs, tag, ax)
%RX_SANITY_CHECK  接收 IQ 数据的"体检"工具 —— 判断谱指标是否可信
%
%   用途: 当频谱/带宽/占用度等指标"不像预期"时, 先用本函数离线排查,
%         把「信号问题」与「测量问题」分开, 避免误判。
%
%   背景: P1 实测 WiFi ch6 时, 谱指标全部异常(动态仅 7.2 dB / 占用带宽 0)。
%         用本函数的三步链定位到根因是 **RxGain 过高导致 ADC 削顶**,
%         而非信号制式问题。
%
%   三步排查链:
%     ① 数据完整性 —— 有无精确零 / 量化级数是否正常   → 排除采集链路丢块
%     ② 硬边界     —— 有无样本越界 / 满量程附近是否堆积 → 判断削顶
%     ③ 分布形态   —— 一维直方图是否出现"悬崖 + 反向堆积"
%
%   用法:
%     report = rx_sanity_check(x, fs)            % x: 复基带 IQ (列向量)
%     report = rx_sanity_check(x, fs, 'P1 ch6')  % 带标签, 只打印不画图
%     rx_sanity_check(x, fs, 'P1')               % 不接收返回值时自动画诊断图
%     rx_sanity_check(x, fs, 'P1', [ax1 ax2 ax3 ax4])  % 画到指定 axes 上 (GUI 友好)
%
%   输入:
%     x   - 复基带 IQ 样本 (Nx1)
%     fs  - 采样率 (Hz), 用于换算时间
%     tag - 可选标签, 出现在打印与图题中
%     ax  - 可选: 1x4 axes 句柄数组 [I直方图 IQ散点 幅度直方图 功率包络]
%           提供则画到指定 axes (不创建新 figure);
%           不提供则按 nargout 决定行为 (nargout=0 画诊断图, =1 不画)
%
%   输出 (struct):
%     .nSamples      总样本数
%     .nUniqueI      I 分量唯一值数 (12 bit ADC 应为 ~4096)
%     .step          量化步长 (12 bit/满量程 2 应为 1/2048)
%     .nExactZero    精确零样本数 (应有 0; 多则疑缓冲补零/丢块)
%     .envMax        峰值幅度 (Pluto 归一化满量程 = 1)
%     .atFullScale   是否触及满量程
%     .edgeRatio     满量程边缘堆积比 (未饱和 ≈0.3, 削顶 >1.2)
%     .clipFrac      触顶样本比例
%     .isClipped     综合判定: 是否 ADC 饱和
%     .verdict       结论字符串
%
%   参考: 实验3-P1-公网信号接收报告.md §6.4

    if nargin < 1
        error('rx_sanity_check: 至少需要 IQ 数据 x');
    end
    if nargin < 2 || isempty(fs),  fs  = 1;        end
    if nargin < 3 || isempty(tag), tag = 'IQ';     end
    if nargin < 4, ax = []; end
    x = x(:);                                       % 强制列向量

    n = numel(x);
    xI = real(x); xQ = imag(x);
    env = abs(x);

    %% ===== ① 数据完整性 =====
    uI       = unique(xI);
    nUniqueI = numel(uI);
    if nUniqueI > 1
        stepI = min(diff(uI));
    else
        stepI = NaN;
    end
    nExactZero = sum(xI == 0 & xQ == 0);

    %% ===== ② 硬边界 / 削顶判定 =====
    envMax = max(env);
    % Pluto(sdrrx, OutputDataType='double') 归一化输出满量程 = 1
    atFullScale = envMax > 0.98;
    % 分量在满量程附近的"反向堆积": 削顶时尾部密度不降反升
    iAbs = abs(xI);
    d1   = mean(iAbs > 0.95);
    d2   = mean(iAbs > 0.85) - d1;
    edgeRatio = d1 / max(d2, eps);
    clipFrac  = mean(env > 0.99*envMax);
    isClipped = atFullScale && edgeRatio > 1.2;

    %% ===== ③ 结论 =====
    if nExactZero > 0.001*n
        verdict = '采集链路可疑: 存在大量精确零 -> 疑 USB 丢块/缓冲补零';
    elseif isClipped
        verdict = 'ADC 饱和(削顶): 谱指标不可信 -> 降 RxGain 至 0~10 dB 重测';
    elseif nUniqueI < 64 && n > 1e5
        verdict = '量化级数异常偏少: 检查位深/归一化设置';
    else
        verdict = '数据健康: 谱指标可用于判读';
    end

    %% ===== 打印 =====
    fprintf('\n===== rx_sanity_check: %s =====\n', tag);
    fprintf('  样本数 %d (%.3f s @ %.3f MHz)\n', n, n/fs, fs/1e6);
    fprintf('  [1] 完整性: 唯一值 %d 级, 步长 %.6f, 精确零 %d (%.4f%%)\n', ...
            nUniqueI, stepI, nExactZero, nExactZero/n*100);
    fprintf('  [2] 边界  : 峰值 %.4f %s | 边缘堆积比 %.2f | 触顶 %.3f%%\n', ...
            envMax, tern(atFullScale,'[满量程]','[未满]'), edgeRatio, clipFrac*100);
    fprintf('  [3] 结论  : %s\n', verdict);
    if isClipped
        fprintf(2, '      → 将 RxGain 降到 0~10 dB, 或拉开天线距离 > 2 m\n');
        fprintf(2, '      → 目标接收平均功率 <= -12 dBFS (OFDM PAPR 10~12 dB 余量)\n');
    end

    %% ===== 输出 =====
    if nargout > 0
        report = struct('nSamples',n, 'nUniqueI',nUniqueI, 'step',stepI, ...
                        'nExactZero',nExactZero, 'envMax',envMax, ...
                        'atFullScale',atFullScale, 'edgeRatio',edgeRatio, ...
                        'clipFrac',clipFrac, 'isClipped',isClipped, ...
                        'verdict',verdict);
    end

    %% ===== 画图 =====
    % 触发条件 (任一):
    %   - 显式提供 axes 句柄 (GUI 调用, nargout 可能 = 0 或 = 1)
    %   - 无返回值且无 axes (脚本式调用, nargout = 0)
    hasAxes = ~isempty(ax) && all(isgraphics(ax));
    if hasAxes
        plotDiagnostics(x, xI, env, fs, tag, isClipped, edgeRatio, ax);
    elseif nargout == 0
        plotDiagnostics(x, xI, env, fs, tag, isClipped, edgeRatio, []);
    end
end

%% ---------- 诊断图 ----------
function plotDiagnostics(x, xI, env, fs, tag, isClipped, edgeRatio, ax)
    if isempty(ax)
        fig = figure('Position',[100 100 900 620],'Color','w');
        ax = gobjects(1,4);
        for k = 1:4, ax(k) = subplot(2,2,k); end
    else
        % 用户提供的 axes: cla 清理
        for k = 1:numel(ax)
            if isgraphics(ax(k)), cla(ax(k)); end
        end
    end

    % (1) I 分量直方图 (看"悬崖+反向堆积")
    axes(ax(1));
    histogram(xI, 80); grid on;
    xlabel('I'); ylabel('计数');
    title(sprintf('I 直方图 (边缘堆积比 %.2f %s)', edgeRatio, ...
          tern(isClipped,'→ 削顶','')));

    % (2) IQ 散点 (削顶时呈填满整格的方形)
    axes(ax(2));
    nDec = max(1, floor(numel(x)/20000));
    plot(real(x(1:nDec:end)), imag(x(1:nDec:end)), '.', 'MarkerSize', 1);
    axis equal; grid on; xlabel('I'); ylabel('Q');
    title('IQ 散点 (削顶时应为填满的方形)');

    % (3) 幅度直方图
    axes(ax(3));
    histogram(env, 80); grid on;
    xlabel('|x|'); ylabel('计数');
    title(sprintf('幅度分布 (峰值 %.3f)', max(env)));

    % (4) 功率包络 (100 段, 看突发/连续)
    axes(ax(4));
    nSeg = 100; segLen = floor(numel(x)/nSeg);
    p = zeros(nSeg,1);
    for i = 1:nSeg
        s = x((i-1)*segLen+1 : i*segLen);
        p(i) = 10*log10(mean(abs(s).^2)+eps);
    end
    plot(((1:nSeg)-0.5)*(segLen/fs)*1e3, p, '-o', 'MarkerSize', 3); grid on;
    xlabel('时间 (ms)'); ylabel('功率 (dBFS)');
    title(sprintf('功率包络 (std %.1f dB; 大=突发, 小=连续)', std(p)));

    if isempty(ax)
        sgtitle(sprintf('rx_sanity_check: %s', tag), 'FontSize', 12);
    end
end

function s = tern(c, a, b)
    if c, s = a; else, s = b; end
end
