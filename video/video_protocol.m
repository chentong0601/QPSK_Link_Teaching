function P = video_protocol()
%VIDEO_PROTOCOL  视频分片协议的常量 (唯一真源)
%
%   一个视频帧 (JPEG 码流) 被拆成 N 个"传输帧", 每个传输帧携带 62 字节载荷:
%
%     ┌──────────┬────────────────────────────────────────────┐
%     │ 分片头 4B │ 视频数据 58B                                │
%     └──────────┴────────────────────────────────────────────┘
%     [0] videoFrameNum  uint8  视频帧号 (0-255 循环)
%     [1] sliceIdx       uint8  片序号 (0 起)
%     [2] totalSlices    uint8  该视频帧总片数 (1-255)
%     [3] dataLen        uint8  本片有效数据字节数 (非末片 = 58)
%
%   设计说明:
%     - 复用现有物理帧载荷 (PayloadSym=248 符号 = 62 字节), 不改动物理层
%     - 4 字节头的必要性: dataLen 用于末片截断 (JPEG 码流长度不是 58 的整数倍)
%     - 上限: 255 片 x 58 B = 14790 B/视频帧; 超出需跨帧拆分 (当前未使用)
%
%   开销: 4/62 = 6.45%

P.PayloadBytes = 62;
P.HeaderBytes  = 4;
P.DataBytes    = 58;
P.MaxSlices    = 255;
P.MaxFrameBytes = 255*58;

end
