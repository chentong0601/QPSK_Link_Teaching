function [payloads, stats] = rx_receiver(rxSource, params, scrambler, rrc, nFrames)
%RX_RECEIVER  通信接收机主循环 (连续接收状态机)
%   与 rx_frame 的区别: rx_frame 处理"一整段已知含帧的波形"一次;
%   本函数模拟真实接收机的**持续工作**: 不断读取数据块, 检测帧, 解调, 输出。
%
%   输入:
%     rxSource : 接收数据源
%                函数句柄 @() ... 返回一块新采样 (硬件: @() rx() )
%                或 向量 (仿真: 按块切分, 末尾自动停止)
%     params   : 参数
%     scrambler: 扰码
%     rrc      : RRC 滤波器
%     nFrames  : 目标接收帧数 (达到后停止)
%   输出:
%     payloads : cell, 每帧 payload 字节
%     stats    : 统计 {nDetected, nDecoded, frameNums, freqEsts, nBlocks}
%
%   接收机状态机:
%     读取缓冲 → 帧检测(滑动相关) → 若检出且帧完整 → 切帧 → 同步+解调 → 输出
%                ↑__________________ 缓冲滑动, 继续下一块 ______________|
%   关键: 维护"滑动缓冲", 保证跨块的帧能被完整捕获;
%         解出后只消费到**该帧末尾**, 不越界啃掉下一帧。

buffer = [];
payloads = {};
stats.nDetected = 0;
stats.nDecoded  = 0;
stats.frameNums = [];
stats.freqEsts  = [];
stats.nBlocks   = 0;

L            = params.SamplesPerSym;
NsymTotal    = params.PreambleSym + params.HeaderSym + params.PayloadSym;
% 一帧自身占用的采样数(不含RRC拖尾); 消费时用它定位"帧末尾"
frameBodyLen = NsymTotal * L;

blockSize = 4096;              % 每次从数据源读取的采样数
isSim     = ~isa(rxSource, 'function_handle');
simLen    = 0;
if isSim, simLen = length(rxSource); end
simPtr    = 1;

maxIter = 4000;                % 保护: 防死循环
iter    = 0;

while stats.nDecoded < nFrames && iter < maxIter
    iter = iter + 1;

    % ================= 1. 读取一块新数据 =================
    if isSim
        if simPtr > simLen
            break;             % 数据源耗尽 (仿真模式)
        end
        idx     = simPtr : min(simPtr+blockSize-1, simLen);
        newData = rxSource(idx);
        simPtr  = idx(end) + 1;
    else
        newData = rxSource();  % 硬件: 阻塞读取一块
        if isempty(newData), continue; end
    end
    buffer = [buffer; newData(:)];
    stats.nBlocks = stats.nBlocks + 1;

    % ================= 2. 在一个缓冲里循环解帧 =================
    % 一块缓冲里可能含多帧 => 反复尝试, 直到解不出为止
    keepGoing = true;
    while keepGoing && stats.nDecoded < nFrames
        try
            [pb, hdr, dg] = rx_frame(buffer, params, scrambler, rrc);
        catch err
            % 未检出 / 帧不完整 => 停止本块的解帧尝试
            if strcmp(err.identifier, 'rx_frame:Incomplete')
                keepGoing = false;      % 数据不够, 等下一块
            else
                % 未检出帧: 丢弃一段, 避免在同一位置反复失败
                if length(buffer) > frameBodyLen
                    buffer = buffer(frameBodyLen+1:end);
                else
                    keepGoing = false;
                end
            end
            continue;
        end

        % ---- 解出一帧 ----
        stats.nDetected = stats.nDetected + 1;
        stats.nDecoded  = stats.nDecoded + 1;
        stats.frameNums(end+1) = hdr.frameNum;
        stats.freqEsts(end+1)  = dg.freqEst;
        payloads{end+1}        = pb;

        % ---- 消费: 丢弃已处理帧(含过渡带), 防止重复解同一帧 ----
        % 帧末尾 = frameStart + 帧体长; 再多丢一个间隔(约 1 符号)让下一帧干净
        consumed = dg.frameStart + frameBodyLen + L;
        if consumed > 0 && consumed <= length(buffer)
            buffer = buffer(consumed+1:end);
        else
            buffer = [];            % 缓冲几乎被消费光
        end
    end

    % ---- 缓冲防溢出: 数据源耗尽且解不出 => 退出 ----
    if isSim && simPtr > simLen && length(buffer) < frameBodyLen
        break;
    end
end

end
