function [st, done, bytes] = video_reassembler(st, payload)
%VIDEO_REASSEMBLER  视频分片重组器 (状态机)
%
%   调用约定:
%     st                = video_reassembler()              % 初始化, 取回状态
%     [st, done, bytes] = video_reassembler(st, payload)   % 推入一片
%
%   输入:
%     st      : 状态结构体 (首次由 video_reassembler() 获得)
%     payload : uint8 62x1, 一个传输帧的载荷
%   输出:
%     st      : 更新后的状态
%     done    : true 表示该视频帧已收齐, bytes 有效
%     bytes   : uint8 列向量, 完整 JPEG 码流
%
%   统计字段: nFramesOK / nFramesDrop / nSlicesRecv / nSlicesDup
%
%   行为:
%     - 按 videoFrameNum 识别视频帧边界
%     - 帧号跳变且上一帧未收齐 => 计为丢帧 (nFramesDrop++)
%     - 重复片不计入, 也不覆盖已有数据
%     - 收齐 totalSlices 片后立即输出并复位, 等待下一帧

P = video_protocol();

% ---------- 初始化 ----------
if nargin == 0 || isempty(st)
    st.frameNum   = -1;
    st.total      = 0;
    st.slices     = {};
    st.nRecv      = 0;
    st.nFramesOK  = 0;
    st.nFramesDrop= 0;
    st.nSlicesRecv= 0;
    st.nSlicesDup = 0;
    done = false; bytes = [];
    return;
end

done = false; bytes = [];

if numel(payload) < P.PayloadBytes
    return;                                   % 长度不足, 丢弃
end
payload = uint8(payload(:));

hdr   = double(payload(1:P.HeaderBytes));
fn    = hdr(1);
idx   = hdr(2) + 1;                           % 转 1 基
tot   = hdr(3);
len   = hdr(4);
data  = payload(P.HeaderBytes+1 : end);

if tot < 1, return; end                       % 非法头

% ---------- 帧边界处理 ----------
if fn ~= st.frameNum
    if st.frameNum >= 0 && st.nRecv < st.total
        st.nFramesDrop = st.nFramesDrop + 1;  % 上一帧未收齐 => 丢帧
    end
    st.frameNum = fn;
    st.total    = tot;
    st.slices   = cell(1, tot);
    st.nRecv    = 0;
end

% ---------- 片索引检查 ----------
if idx < 1 || idx > st.total
    return;
end

% ---------- 存入 ----------
if isempty(st.slices{idx})
    if idx < st.total
        st.slices{idx} = data;                              % 非末片: 满 58 B
    else
        L = min(double(len), numel(data));                  % 末片: 按 dataLen 截断
        st.slices{idx} = data(1:L);
    end
    st.nRecv       = st.nRecv + 1;
    st.nSlicesRecv = st.nSlicesRecv + 1;
else
    st.nSlicesDup = st.nSlicesDup + 1;                      % 重复片
end

% ---------- 收齐判定 ----------
if st.nRecv == st.total
    bytes = vertcat(st.slices{:});
    st.nFramesOK = st.nFramesOK + 1;
    done = true;
    % 复位
    st.frameNum = -1;
    st.total    = 0;
    st.slices   = {};
    st.nRecv    = 0;
end

end
