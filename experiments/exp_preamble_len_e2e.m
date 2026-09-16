%% experiments/exp_preamble_len_e2e.m
% 目的: 验证"加长前导"能否真正修复帧内相位斜坡缺陷 (端到端)
% 背景: experiments/exp_freq_estimator.m 证明:
%   - 估计器算法已无提升空间 (ML 仅比现状好 7%; 重复结构反而差 7.6%)
%   - 唯一有效杠杆是加长前导: p=32->64 使 sigma_f 降到 1/2.85, 漂移 58度->22.6度
% 本脚本: 端到端测 帧成功率 + 频偏估计标准差 + 帧内漂移
% 用法: matlab -batch "addpath('experiments'); exp_preamble_len_e2e"

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params0 = init_params;
bp = params0.bitsPerSym; L = params0.SamplesPerSym;
rrc0 = rcosdesign(params0.RollOff, params0.RRCSpan, L, 'sqrt');
Lp = length(rrc0);

nF = 20; freqOffset = 320; nRep = 3;

fprintf('\n############ 加长前导 端到端验证 ############\n');
fprintf('%d 帧/次, %d 次重复, 频偏 %d Hz, 满载荷 62 字节\n\n', nF, nRep, freqOffset);

for dB = [10 12 14]
    fprintf('=== Eb/N0 = %d dB ===\n', dB);
    fprintf('%6s | %8s | %10s | %12s | %14s | %12s\n', ...
            'p', '帧效率', '帧成功率', 'freqEst std', '帧长(符号)', '帧内漂移');
    fprintf('%s\n', repmat('-', 1, 74));
    for p = [32 48 64 96]
        params = params0;
        params.PreambleSym = p;
        [~, scrambler, ~] = gen_frame_sequences(params);
        Nsym = p + params.HeaderSym + params.PayloadSym;
        eff = 248/Nsym*100;

        totOK = 0; totN = 0; feAll = [];
        for tr = 1:nRep
            rng(200*tr + dB);
            contWave = []; msgs = {};
            for k = 1:nF
                m = [sprintf('PKT-%03d-', k-1) repmat('X', 1, 54)];
                msgs{k} = m;
                fSym = tx_frame(int8(m(:)), params, 0, mod(k-1,256));
                [w, ~] = tx_baseband(fSym, L, rrc0);
                w = w * 0.9/max(abs(w));
                if k == 1, Es = L*mean(abs(w).^2); end
                contWave = [contWave; w; zeros(80,1)]; %#ok<AGROW>
            end
            nn = (0:length(contWave)-1).';
            contWave = contWave .* exp(1j*2*pi*freqOffset*nn/params.SampleRate);
            sigma = sqrt(Es/(2*10^(dB/10)*bp));
            contWave = contWave + sigma*(randn(size(contWave))+1j*randn(size(contWave)));

            [pbs, st] = rx_receiver(contWave, params, scrambler, rrc0, nF);
            for i = 1:length(pbs)
                t = strtrim(char(pbs{i}(:)).');
                if any(strcmp(t, msgs)), totOK = totOK + 1; end
            end
            totN = totN + nF;
            feAll = [feAll, st.freqEsts]; %#ok<AGROW>
        end
        stdFe = std(feAll);
        drift = stdFe*360*Nsym/params.SymbolRate;
        fprintf('%6d | %7.1f%% | %9.1f%% | %11.1f Hz | %14d | %11.1f 度\n', ...
                p, eff, totOK/totN*100, stdFe, Nsym, drift);
    end
    fprintf('\n');
end
