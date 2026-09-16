function rxGainBest = e4_ant_calib(link, targetDbfs)
%E4_ANT_CALIB  接收增益标定 —— 让三组不同链路/天线的接收功率对齐
%
%   【为什么必须标定】
%     不同天线的耦合损耗不同。若三组沿用同一个 RxGain, 接收功率就会不同,
%     那么最后测出的差异里 "天线差异" 与 "增益差异" 是混在一起的, 结论不成立。
%     本脚本扫描 RxGain, 找到使接收平均功率最接近目标值的那一档,
%     从而保证三组的**唯一自变量是"连接方案"**。
%
%   【用法】(必须在 MATLAB GUI 中运行)
%     rxGain = e4_ant_calib('coax')          % 目标 -25 dBFS (默认)
%     rxGain = e4_ant_calib('short', -25)
%     rxGain = e4_ant_calib('long',  -25)
%
%   【建议流程】
%     for 每组链路:
%       1) 接好硬件
%       2) rxGain = e4_ant_calib('<link>')     % 标定
%       3) main_e4_hw_runall('<link>', rxGain) % 用标定值正式采集
%
%   输出: rxGainBest — 推荐的 RxGain (dB); 结果同时存 results/e4/antenna/
%
%   实现: 用一小段探针波形 (含若干传输帧) 扫 RxGain, 记录接收平均功率。

    if nargin < 1 || isempty(link),       link = 'coax';        end
    if nargin < 2 || isempty(targetDbfs), targetDbfs = -25;      end

    thisDir = fileparts(mfilename('fullpath'));
    cd(fileparts(thisDir));
    addpath('config'); addpath('transmitter'); addpath('receiver');
    addpath('sync'); addpath('video'); addpath('experiments');

    params = init_params;
    L  = params.SamplesPerSym;
    rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
    [~, scrambler, ~] = gen_frame_sequences(params);

    %% ===== 探针: 10 个独立传输帧 (每段 58 B -> 1 片) =====
    nProbe = 10;
    probeC = cell(1, nProbe);
    for k = 1:nProbe
        probeC{k} = uint8(repmat(k-1, 58, 1));       % 每段内容不同, 便于识别
    end
    gainList = 0:5:60;                               % 待扫 RxGain

    fprintf('\n################################################################\n');
    fprintf('#   E4 接收增益标定 —— link = %s\n', link);
    fprintf('#   目标接收功率: %.1f dBFS\n', targetDbfs);
    fprintf('################################################################\n');

    %% ===== 0. 设备自检 (失败立即退出, 避免逐档无效尝试) =====
    fprintf('\n检查 Pluto 设备 ...\n');
    radios = [];
    try
        radios = findPlutoRadio();
    catch ME
        fprintf(2, '  findPlutoRadio 调用失败: %s\n', ME.message);
    end
    if isempty(radios)
        fprintf(2, '\n[!] 未发现 Pluto 设备, 标定中止。请按顺序排查:\n');
        fprintf(2, '    ① 【最常见】设备被占用: 先执行  clear all; close all;  再重试\n');
        fprintf(2, '       (之前的 sdrtx/sdrrx 对象未释放会锁住 Pluto)\n');
        fprintf(2, '    ② USB 线是否插紧 (Pluto 应有绿色 LED 常亮; ping 192.168.2.1)\n');
        fprintf(2, '    ③ 手动运行 findPlutoRadio 是否能看到设备\n');
        fprintf(2, '    ④ 以上都正常仍失败 -> 拔插 USB 线后重试\n');
        rxGainBest = NaN;
        return;
    end
    ids = arrayfun(@(r) string(r.RadioID), radios);
    fprintf('  发现 %d 台 Pluto: %s\n', numel(radios), strjoin(cellstr(ids), ', '));

    txGain = -20;
    res = struct('gain', {}, 'pwr', {}, 'nOK', {});
    nFail = 0;
    for gi = 1:numel(gainList)
        g = gainList(gi);
        opt.mode = 'hw'; opt.link = link;
        opt.txGain = txGain; opt.rxGain = g;
        opt.nRep = 1;                 % 标定只需 1 个周期, 省时
        opt.verbose = false;
        try
            [~, stt] = e4_hw_link(probeC, params, rrc, scrambler, opt);
            nFail = 0;
            res(end+1) = struct('gain', g, 'pwr', stt.rxPowerDbfs, 'nOK', stt.nFramesOK); %#ok<AGROW>
            fprintf('  RxGain %2d dB -> 接收功率 %7.1f dBFS | 解出帧 %d/%d\n', ...
                g, stt.rxPowerDbfs, stt.nFramesOK, nProbe);
        catch ME
            nFail = nFail + 1;
            fprintf(2, '  RxGain %2d dB -> 失败: %s\n', g, ME.message);
            if nFail >= 3
                fprintf(2, '\n[!] 连续 %d 档失败, 停止扫描 (避免无意义等待)。\n', nFail);
                fprintf(2, '    最可能原因: 硬件连接异常。请检查 USB / findPlutoRadio。\n');
                break;
            end
        end
    end

    if isempty(res)
        fprintf(2, '\n[!] 全部增益档均失败, 无法标定。\n');
        rxGainBest = 30;
        return;
    end

    %% ===== 选最接近目标的档位 =====
    % 优先选"未饱和"且功率最接近目标的; 若都饱和, 选功率最低的档
    pwr = [res.pwr];
    satLimit = -3;                                % 超过 -3 dBFS 视为接近饱和
    cand = find(pwr <= satLimit);
    if isempty(cand)
        [~, ib] = min(pwr);
        fprintf(2, '\n[!] 所有档位均接近/达到饱和 (最高 %.1f dBFS), 建议加衰减器或拉开天线。\n', max(pwr));
    else
        [~, rel] = min(abs(pwr(cand) - targetDbfs));
        ib = cand(rel);
    end
    rxGainBest = res(ib).gain;

    fprintf('\n===== 标定结果 =====\n');
    fprintf('  推荐 RxGain = %d dB (接收功率 %.1f dBFS, 目标 %.1f dBFS)\n', ...
        rxGainBest, res(ib).pwr, targetDbfs);
    fprintf('  下一步: main_e4_hw_runall(''%s'', %d)\n', link, rxGainBest);

    %% ===== 落盘 =====
    outdir = fullfile('results', 'e4', 'antenna');
    if ~isfolder(outdir), mkdir(outdir); end
    tsTag = datestr(now, 'yyyymmdd_HHMMSS');

    cfg = struct('link', link, 'biz', 'calib', 'mode', 'hw', ...
                 'centerFreq', params.CenterFrequency, 'sampleRate', params.SampleRate, ...
                 'txGain', txGain, 'targetDbfs', targetDbfs, ...
                 'timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    metrics = struct('rxGainBest', rxGainBest, 'pwrBest', res(ib).pwr, ...
                     'gainList', gainList, 'pwrList', pwr);
    raw = struct('res', res);
    fn = fullfile(outdir, sprintf('ant_calib_%s_%s.mat', link, tsTag));
    save(fn, 'cfg', 'metrics', 'raw');
    fprintf('  [OK] 标定数据已存 %s\n', fn);
    fprintf('################################################################\n\n');
end
