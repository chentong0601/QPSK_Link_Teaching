function [rxIQ, st] = e4_hw_rawtxrx(wave, params, opt)
%E4_HW_RAWTXRX  裸基带波形收发 —— 循环发射给定波形, 采集 N 个周期, 返回原始 IQ
%
%   与 e4_hw_link 的区别:
%     e4_hw_link    : 输入【字节】, 内部完成 分片→组帧→成形→收发→解调→重组
%     本函数        : 输入【已成形波形】, 只做 发射↔采集, 不做任何协议处理
%   ⇒ 用于需要拿到【原始 IQ】的场景 (EVM / 星座图 / 频谱 / 同步分析)
%
%   ⚠️ 必须在 MATLAB GUI 中运行 (sdrtx/sdrrx 在 -batch 下不可用)
%
%   输入:
%     wave   : 基带波形 (复数列向量), 建议已归一化到 ~0.9
%     params : 参数结构体 (取 CenterFrequency / SampleRate)
%     opt    : 可选字段
%              .txGain 发射增益 dB (默认 -20)
%              .rxGain 接收增益 dB (默认 30)
%              .nRep   采集周期数 (默认 2)
%              .spf    SamplesPerFrame (默认 8192)
%              .verbose 打印过程 (默认 true)
%
%   输出:
%     rxIQ : 接收原始 IQ (复列向量, 已去直流)
%     st   : {rxPowerDbfs, capTime, nSamples}
%
%   用法:
%     [iq, st] = e4_hw_rawtxrx(wave, params, struct('rxGain', 30, 'nRep', 2));

    if nargin < 3 || isempty(opt), opt = struct(); end
    if ~isfield(opt, 'txGain'),  opt.txGain = -20;   end
    if ~isfield(opt, 'rxGain'),  opt.rxGain = 30;    end
    if ~isfield(opt, 'nRep'),    opt.nRep = 2;       end
    if ~isfield(opt, 'spf'),     opt.spf = 8192;     end
    if ~isfield(opt, 'verbose'), opt.verbose = true; end

    wave = wave(:);
    waveLen = numel(wave);

    tx = []; rx = []; rxIQ = [];
    t0 = tic;
    try
        tx = sdrtx('Pluto');
        tx.CenterFrequency    = params.CenterFrequency;
        tx.BasebandSampleRate = params.SampleRate;
        tx.Gain               = opt.txGain;
        tx.OutputDataType     = 'double';
        transmitRepeat(tx, wave);
        if opt.verbose
            fprintf('    [裸收发] 已循环发射 %.4f s 波形 (TxGain=%d dB)\n', ...
                    waveLen/params.SampleRate, opt.txGain);
        end

        rx = sdrrx('Pluto');
        rx.CenterFrequency    = params.CenterFrequency;
        rx.BasebandSampleRate = params.SampleRate;
        rx.GainSource         = 'Manual';
        rx.Gain               = opt.rxGain;
        rx.SamplesPerFrame    = opt.spf;
        rx.OutputDataType     = 'double';

        for i = 1:3, rx(); end          % 丢弃瞬态

        nBlk = ceil(waveLen * opt.nRep / opt.spf);
        rxIQ = zeros(nBlk * opt.spf, 1);
        for i = 1:nBlk
            rxIQ((i-1)*opt.spf + 1 : i*opt.spf) = rx();
        end
        capT = toc(t0);
    catch ME
        fprintf(2, '[裸收发失败] %s\n', ME.message);
        try, if ~isempty(rx), release(rx); end, catch, end
        try, if ~isempty(tx), release(tx); end, catch, end
        rethrow(ME);
    end
    try, release(rx); catch, end
    try, release(tx); catch, end

    rxIQ = rxIQ - mean(rxIQ);
    st = struct('rxPowerDbfs', 20*log10(sqrt(mean(abs(rxIQ).^2)) + eps), ...
                'capTime', capT, 'nSamples', numel(rxIQ));

    if opt.verbose
        fprintf('    [裸收发] 采集 %d 采样 (%.3f s), %.2f s 完成, 功率 %.2f dBFS\n', ...
                numel(rxIQ), numel(rxIQ)/params.SampleRate, capT, st.rxPowerDbfs);
    end
end
