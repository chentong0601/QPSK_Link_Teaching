function [preambleSym, scrambler, preambleWave, preambleBits] = frame_sequences_cached(params, rrc)
%FRAME_SEQUENCES_CACHED  收发共享的帧序列 (带缓存)
%
%   为什么需要 (性能剖析数据, experiments/prof_rx_frame.m):
%     tx_frame / rx_frame 原本【每处理一帧】都调用 gen_frame_sequences 重建序列,
%     并 (在接收端) 重算前导成形波形。实测这些常量计算占单帧耗时的 20%~50%:
%       - rx_frame: 前导波形构造 20.8% (其中 gen_frame_sequences 18.7%)
%       - tx_frame: 同样每帧调用 (发射端 476 帧耗时 1.23 s, 合 2.6 ms/帧)
%     而这些序列都是【常量】(固定种子生成)。
%
%   顺带修复一个隐患:
%     gen_frame_sequences 内部有 `rng(42)` 重置 —— 每帧调用会反复破坏全局
%     随机数状态。若调用方在同一脚本中还要用 randn/randi, 结果将被隐式影响。
%     缓存后不再重复调用, 消除该副作用。
%
%   输入:
%     params : 参数结构体
%     rrc    : (可选) RRC 滤波器; 提供时才计算 preambleWave
%   输出:
%     preambleSym  : 前导 QPSK 符号 (PreambleSym x 1)
%     scrambler    : 载荷扰码比特 (PayloadSym*bitsPerSym x 1)
%     preambleWave : 前导成形波形 (采样域); 未传 rrc 时为空
%     preambleBits : 前导比特 (PreambleSym*bitsPerSym x 1)

persistent cache

key = [params.PreambleSym, params.PayloadSym, params.M, ...
       params.SamplesPerSym, params.RollOff, params.RRCSpan];

if isempty(cache) || ~isequal(cache.key, key) || ...
        (nargin >= 2 && ~isempty(rrc) && numel(cache.preambleWave) ~= ...
         params.PreambleSym*params.SamplesPerSym + numel(rrc) - 1)
    [pb, sc, ps] = gen_frame_sequences(params);
    L = params.SamplesPerSym;
    up = zeros(params.PreambleSym*L, 1);
    up(1:L:end) = ps;
    cache.preambleBits = pb;
    cache.preambleSym  = ps;
    cache.scrambler    = sc;
    cache.preambleWave = [];
    cache.key = key;
end

% 前导成形波形按需计算并缓存 (仅接收端需要)
if nargin >= 2 && ~isempty(rrc) && isempty(cache.preambleWave)
    L = params.SamplesPerSym;
    up = zeros(params.PreambleSym*L, 1);
    up(1:L:end) = cache.preambleSym;
    cache.preambleWave = conv(up, rrc);
end

preambleSym  = cache.preambleSym;
scrambler    = cache.scrambler;
preambleBits = cache.preambleBits;
if nargin >= 2 && ~isempty(rrc)
    preambleWave = cache.preambleWave;
else
    preambleWave = [];
end

end
