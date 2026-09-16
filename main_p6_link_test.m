%% main_p6_link_test.m
% P6a  空口链路质量评估 —— 测量【单传输帧成功率 p】
%
%   ⚠️ 必须在 MATLAB GUI 中运行！
%      (-batch 模式下 Support Package 路径未注册, sdrtx/sdrrx 不可用)
%
%   为什么要先做这一步:
%     一个视频帧需要 N 个传输帧【全部到齐】才能解码, 故
%         视频帧完成率 = p^N
%     必须先测出空口的真实 p, 才能定 N (即分辨率/质量)。
%     这是"先量化, 再配置"的原则 (与 W7a 决策评估同一方法论)。
%
%   硬件接法 (与 W3 相同):
%     Pluto 的 TX 口与 RX 口各接一根天线, 间距 ≥10 cm;
%     或 TX/RX 之间用衰减器有线连接 (更稳定, 推荐首次联调)
%
%   用法: 在 MATLAB GUI 中打开本文件, 按 F5 运行 (不要用 -batch)

clear; clc; close all;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync'); addpath('video');

%% ===== 配置 =====
CFG.nF        = 100;            % 每次发射的传输帧数
CFG.nRep      = 3;              % 抓取几个发射周期
CFG.gainList  = [30 40 50];     % 要测试的 RxGain (dB)
CFG.TxGain    = -20;            % 发射增益
CFG.captureOnce = false;        % true = 只测 gainList(1); false = 扫描全部
CFG.dryRun    = false;          % ★ 首次使用建议先改 true 自检, 再改 false 接硬件
CFG.dryRunSNR = 12;             % dryRun 时的 Eb/N0 (dB)

params = init_params;
L  = params.SamplesPerSym;
bp = params.bitsPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

fprintf('\n');
fprintf('################################################################\n');
fprintf('#   P6a  空口链路质量评估                                       #\n');
fprintf('################################################################\n');
fprintf('中心频率 %.3f GHz  采样率 %.0f kHz  TxGain %d dB  帧数/次 %d\n', ...
        params.CenterFrequency/1e9, params.SampleRate/1e3, CFG.TxGain, CFG.nF);

%% ===== 1. 组帧 (载荷含序号, 便于统计丢帧) =====
fprintf('\n===== 1. 组帧 =====\n');
msgs = cell(1, CFG.nF);
segs = {};
for k = 1:CFG.nF
    m = [sprintf('LNK-%03d-', k-1) repmat('.', 1, 54)];   % 62 字节
    msgs{k} = m;
    fS = tx_frame(uint8(m(:)), params, 0, mod(k-1,256));
    [w, ~] = tx_baseband(fS, L, rrc);
    w = w * 0.9 / max(abs(w));
    if isempty(segs), Es = L*mean(abs(w).^2); end
    segs{end+1} = [w; zeros(80,1)]; %#ok<AGROW>
end
wave = vertcat(segs{:});
waveLen = numel(wave);
fprintf('  波形长度 %d 采样 = %.3f s (一个发射周期)\n', waveLen, waveLen/params.SampleRate);
fprintf('  抓取 %d 个周期 = %d 采样\n', CFG.nRep, waveLen*CFG.nRep);

%% ===== 2. 硬件收发 =====
if CFG.captureOnce, gainList = CFG.gainList(1); else, gainList = CFG.gainList; end
nG = numel(gainList);
res = struct('gain',{},'nOK',{},'p',{},'freqEst',{},'rho',{},'rxData',{});

if CFG.dryRun
    % ---------- 自检模式: 不接硬件, 用仿真信道 ----------
    % 目的: 在接硬件前验证本脚本的组帧/解码/统计逻辑是否正确
    fprintf('\n[DRY-RUN] 跳过硬件, 使用仿真信道 (Eb/N0 = %d dB, 频偏 320 Hz)\n', CFG.dryRunSNR);
    nn = (0:numel(wave)-1).';
    rw = wave .* exp(1j*2*pi*320*nn/params.SampleRate);
    sg = sqrt(Es/(2*10^(CFG.dryRunSNR/10)*bp));
    rw = rw + sg*(randn(size(rw)) + 1j*randn(size(rw)));
    rxData = repmat(rw, CFG.nRep, 1);            % 模拟多个周期
    rxData = rxData - mean(rxData);

    [pbs, st] = rx_receiver(rxData, params, scrambler, rrc, CFG.nF*CFG.nRep);
    nOK = 0; hitIdx = [];
    for i = 1:numel(pbs)
        t = strtrim(char(pbs{i}(:)).');
        idx = find(strcmp(t, msgs), 1);
        if ~isempty(idx), nOK = nOK + 1; hitIdx(end+1) = idx; end %#ok<AGROW>
    end
    nSentUniq = numel(unique(hitIdx));
    pEst = nSentUniq / CFG.nF;
    fprintf('  解出传输帧 %d 个 (唯一帧 %d / %d)\n', nOK, nSentUniq, CFG.nF);
    fprintf('  ★ 自检单帧成功率 p = %.4f  (仿真信道下应接近 1.0)\n', pEst);
    if ~isempty(st.freqEsts)
        fprintf('  频偏估计: 均值 %.1f Hz, 标准差 %.1f Hz (真值 320 Hz)\n', ...
                mean(st.freqEsts), std(st.freqEsts));
    end
    res(1).gain = -1;  res(1).nOK = nOK;  res(1).p = pEst;
    res(1).freqEst = st.freqEsts;  res(1).rxData = [];

    % 分片预算演示
    slice_budget(pEst, 0.5, 'SlicesForRes', [144 176 50; 120 160 50; 240 320 50], 'ref');
    fprintf('\n[DRY-RUN] 脚本逻辑自检完成。把 CFG.dryRun 改为 false 即可接硬件。\n');
    fprintf('\n################################################################\n');
    fprintf('#   P6a 自检完成                                                #\n');
    fprintf('################################################################\n\n');
    return;
end

tx = [];
try
    tx = sdrtx('Pluto');
    tx.CenterFrequency    = params.CenterFrequency;
    tx.BasebandSampleRate = params.SampleRate;
    tx.Gain               = CFG.TxGain;
    tx.OutputDataType     = 'double';
    transmitRepeat(tx, wave);
    fprintf('\n[OK] 已开始循环发射 (TxGain=%d dB)\n', CFG.TxGain);

    for gi = 1:nG
        g = gainList(gi);
        fprintf('\n----- RxGain = %d dB -----\n', g);

        % 每次重新创建接收对象以设置增益
        rx = sdrrx('Pluto');
        rx.CenterFrequency    = params.CenterFrequency;
        rx.BasebandSampleRate = params.SampleRate;
        rx.GainSource         = 'Manual';
        rx.Gain               = g;
        rx.SamplesPerFrame    = 8192;
        rx.OutputDataType     = 'double';

        % 先丢弃若干个块 (让 AGC/滤波器稳定, 避开起始瞬态)
        for i = 1:3, rx(); end

        nBlk  = ceil(waveLen*CFG.nRep / 8192);
        rxData = zeros(nBlk*8192, 1);
        t0 = tic;
        for i = 1:nBlk
            rxData((i-1)*8192+1 : i*8192) = rx();
        end
        capT = toc(t0);
        fprintf('  抓取 %d 采样, 用时 %.2f s\n', numel(rxData), capT);

        % 去直流 (空口零中频偏置; 实测很小, 但无害)
        rxData = rxData - mean(rxData);

        % 离线解码
        fprintf('  解码中 ...\n');
        [pbs, st] = rx_receiver(rxData, params, scrambler, rrc, CFG.nF*CFG.nRep);
        nOK = 0; hitIdx = [];
        for i = 1:numel(pbs)
            t = strtrim(char(pbs{i}(:)).');
            idx = find(strcmp(t, msgs), 1);
            if ~isempty(idx), nOK = nOK + 1; hitIdx(end+1) = idx; end %#ok<AGROW>
        end
        % 单帧成功率: 以"发送帧数 x 周期数"为分母 (可能重复收到同一帧)
        nSentUniq = numel(unique(hitIdx));
        pEst = nSentUniq / CFG.nF;
        fe = st.freqEsts;
        fprintf('  解出传输帧 %d 个 (唯一帧 %d / %d)\n', nOK, nSentUniq, CFG.nF);
        fprintf('  ★ 单传输帧成功率 p = %.4f\n', pEst);
        if ~isempty(fe)
            fprintf('  频偏估计: 均值 %.1f Hz, 标准差 %.1f Hz\n', mean(fe), std(fe));
        end

        res(gi).gain = g;  res(gi).nOK = nOK;  res(gi).p = pEst;
        res(gi).freqEst = fe;  res(gi).rxData = rxData;

        release(rx);
        clear rx;
    end
catch e
    fprintf('\n[!!] 硬件操作失败: %s\n', e.message);
    fprintf('     排查: ① Pluto 是否连接(findPlutoRadio) ② 是否在 GUI 中运行\n');
    fprintf('           ③ Support Package 是否安装 ④ 天线是否接好\n');
end

% 清理硬件
try, if ~isempty(tx), release(tx); end, catch, end
fprintf('\n[OK] 已停止发射并释放硬件\n');

%% ===== 3. 结果汇总与配置建议 =====
if ~isempty(res) && ~isempty(res(1).gain)
    fprintf('\n===== 结果汇总 =====\n');
    fprintf('%10s | %12s | %10s\n','RxGain','单帧成功率','等效估计');
    fprintf('%s\n', repmat('-',1,38));
    for i = 1:numel(res)
        fprintf('%8d dB | %11.2f%% | %10.4f\n', res(i).gain, res(i).p*100, res(i).p);
    end
    [pBest, ib] = max([res.p]);
    fprintf('\n最佳: RxGain = %d dB, p = %.4f\n', res(ib).gain, pBest);

    % 分片预算
    fprintf('\n');
    slice_budget(pBest, 0.5, 'SlicesForRes', [144 176 50; 120 160 50; 240 320 50], 'ref');

    if pBest < 0.9
        fprintf('[!!] p < 0.9: 空口质量偏低, 视频难以完成。建议:\n');
        fprintf('     ① 缩短天线间距 / 改用有线+衰减器 ② 调整 RxGain\n');
        fprintf('     ③ 降低符号率 (params.SymbolRate) 以提高每符号能量\n');
    elseif pBest < 0.99
        fprintf('[!] 0.9 <= p < 0.99: 视频可用但会明显丢帧。\n');
        fprintf('    建议采用 slice_budget 给出的低分辨率配置。\n');
    else
        fprintf('[OK] p >= 0.99: 可支持 320x240 级视频 (见上表)。\n');
    end

    % 保存结果 (文件名含 gainList, 不同配置不互覆盖)
    if ~isfolder('results'), mkdir('results'); end
    gainTag = strjoin(arrayfun(@(g) sprintf('%d',round(g)), CFG.gainList, 'UniformOutput',false), '-');
    fn = sprintf('results/p6a_g%s_%s.mat', gainTag, datestr(now,'yyyymmdd_HHMMSS'));
    save(fn, 'res', 'CFG', '-v7.3');
    fprintf('[OK] 数据已保存 %s (可离线反复分析)\n', fn);
else
    fprintf('\n[!!] 未获得有效结果\n');
end

fprintf('\n################################################################\n');
fprintf('#   P6a 完成                                                    #\n');
fprintf('################################################################\n\n');
