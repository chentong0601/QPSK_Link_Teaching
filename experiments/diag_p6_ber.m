%experiments/diag_p6_ber.m  空口物理层字节正确率 (用 P6a 真实 rxData)
%  方法: 用项目自身的连续接收机解调 P6a 抓取的真实空口波形,
%        与发射端已知载荷逐字节比对, 统计真实误码率 (BER)
%  目的: 判定 P6b 图像 PSNR 17dB 是否源于物理层误码
%  用法: matlab -batch "addpath('experiments'); diag_p6_ber"

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params; L = params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

% 重建 P6a 真值消息 (62 字节, 与 main_p6_link_test 完全一致)
nF = 100;
msgsC = cell(1, nF);
for k = 1:nF
    msgsC{k} = [sprintf('LNK-%03d-', k-1) repmat('.', 1, 54)];
end

d = dir('results/p6_link_*.mat');
[~, idx] = max([d.datenum]);
S = load(fullfile(d(idx).folder, d(idx).name));
fprintf('数据: %s\n', d(idx).name);

for g = 1:numel(S.res)
    rxd = S.res(g).rxData;
    if isempty(rxd), continue; end
    fprintf('\n===== RxGain = %d dB =====\n', S.res(g).gain);

    [pbs, st] = rx_receiver(rxd(:), params, scrambler, rrc, 3*nF);
    fprintf('  解出帧数 %d (期望 300 = 3 周期 x 100)\n', numel(pbs));

    nExact = 0; nTot = 0; nByteErrTot = 0; nFrameErr = 0;
    errPos = [];
    for i = 1:numel(pbs)
        t = char(pbs{i}(:)).';
        nTot = nTot + 1;
        idxm = find(strcmp(t, msgsC), 1);
        if ~isempty(idxm)
            nExact = nExact + 1;
        else
            nFrameErr = nFrameErr + 1;
            % 找最接近的真值 (按序号前缀)
            pre = t(1:min(7,numel(t)));
            j = find(strncmp(pre, msgsC, 7), 1);
            if ~isempty(j)
                a = uint8(t); b = uint8(msgsC{j});
                nb = min(numel(a), numel(b));
                ne = sum(a(1:nb) ~= b(1:nb)) + abs(numel(a)-numel(b));
                nByteErrTot = nByteErrTot + ne;
                errPos = [errPos, find(a(1:nb) ~= b(1:nb))]; %#ok<AGROW>
            end
        end
    end
    fprintf('  ★ 字节完全正确: %d / %d (%.2f%%)\n', nExact, nTot, nExact/nTot*100);
    if nFrameErr > 0
        fprintf('  错误帧 %d 个, 平均错误字节 %.2f B/帧\n', nFrameErr, nByteErrTot/max(nFrameErr,1));
        if ~isempty(errPos)
            fprintf('  错误字节位置分布: 前导后第 [%s] 字节 (共%d处)\n', ...
                    num2str(unique(errPos(1:min(end,20)))), numel(errPos));
        end
    end
    if ~isempty(st.freqEsts)
        fprintf('  频偏 %.1f ± %.1f Hz\n', mean(st.freqEsts), std(st.freqEsts));
    end
end

fprintf('\n===== 结论指引 =====\n');
fprintf('  若"字节完全正确"接近 100%% => 物理层无误码, P6b 问题在视频层/分片协议\n');
fprintf('  若明显低于 100%%          => 物理层误码, 需降低 RxGain 或加保护\n');