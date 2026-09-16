%% ===== W6: 通信接收机 (连续接收) 验证 =====
% 目的: 验证接收机能"持续工作"——从连续数据流中连续解出多帧
% 与 rx_frame(单帧) 的区别: 本验证模拟真实接收机的连续接收场景
% 用法: matlab -batch "main_w6_receiver"

clear; clc;
addpath('config'); addpath('transmitter'); addpath('receiver'); addpath('sync');
params = init_params;
M=params.M; bp=params.bitsPerSym; L=params.SamplesPerSym;
rrc = rcosdesign(params.RollOff, params.RRCSpan, L, 'sqrt');
[~, scrambler, ~] = gen_frame_sequences(params);

nF = 20;                      % 连续 20 帧 (比 5 帧更接近真实持续接收)
freqOffset = 320;             % 注入真实载波频偏 Hz (模拟晶振误差)
EbN0dB = 12;

%% ---- 生成连续多帧数据流 (模拟发射端循环发射) ----
% ★ 修正记录 (2026-09-10): 原版用 10 字节短消息, 会系统性掩盖误码
%   (误码集中在帧尾, 短消息只占载荷区前 40 符号, 其余错误落在被丢弃的补零区)。
%   本版改为【满载荷 62 字节】。详见 notes/exp_baseline_metrics.md §E4
PAD = repmat('X', 1, 62-8);   % 补齐到 62 字节 (载荷上限)
t = 0; contWave = []; msgs = {}; trueStart = [];
for k = 1:nF
    m = [sprintf('PKT-%03d-', k-1) PAD];
    msgs{k} = m;
    fSym = tx_frame(int8(m(:)), params, 0, mod(k-1,256));
    [w, ~] = tx_baseband(fSym, L, rrc);
    w = w * 0.9/max(abs(w));
    if k == 1, Es = L * mean(abs(w).^2); end     % 单帧符号能量(不含帧间补零)
    trueStart(k) = length(contWave)+1;
    contWave = [contWave; w; zeros(80,1)];   %#ok<AGROW> 帧间间隔
end
fprintf('[OK] 生成 %d 帧连续数据流 (满载荷 62 字节), 共 %d 采样\n', nF, length(contWave));

%% ---- 加频偏 + 加噪 (模拟真实信道) ----
n = (0:length(contWave)-1).';
contWave = contWave .* exp(1j*2*pi*freqOffset*n/params.SampleRate);
% 噪声按实际符号能量标定 (修正原版隐含 Es=1 使 Eb/N0 偏高 ~1.83 dB 的问题)
sigma = sqrt(Es/(2*10^(EbN0dB/10)*bp));
contWave = contWave + sigma*(randn(size(contWave))+1j*randn(size(contWave)));
fprintf('[OK] 注入频偏 %d Hz, Eb/N0 = %d dB\n', freqOffset, EbN0dB);

%% ---- 连续接收 ----
fprintf('\n===== 连续接收机运行 =====\n');
[payloads, stats] = rx_receiver(contWave, params, scrambler, rrc, nF);

%% ---- 验证 ----
fprintf('接收帧数: %d / %d  (读取块数 %d)\n', stats.nDecoded, nF, stats.nBlocks);
fprintf('帧号序列: '); fprintf('%d ', stats.frameNums(1:min(25,end))); fprintf('\n');
fprintf('频偏估计: 均值 %.1f Hz  标准差 %.1f Hz (注入 %d Hz)\n', ...
    mean(stats.freqEsts), std(stats.freqEsts), freqOffset);

okCnt = 0; orderOK = true;
for i = 1:length(payloads)
    txt = strtrim(char(payloads{i}(:)).');
    if any(strcmp(txt, msgs)), okCnt = okCnt + 1; end
    if i <= length(stats.frameNums) && stats.frameNums(i) ~= i-1, orderOK = false; end
    if mod(i-1,5)==0 || i==length(payloads)
        fprintf('  帧%d: "%s"\n', i-1, txt);
    end
end
fprintf('  ... (共 %d 帧)\n', length(payloads));
fprintf('\n正确帧数 = %d/%d  |  帧序连续 = %s\n', okCnt, nF, string(orderOK));
if okCnt == nF && orderOK
    fprintf('[PASS] 连续接收机工作正常!\n');
else
    fprintf('[PARTIAL] 部分帧未正确解出\n');
end
