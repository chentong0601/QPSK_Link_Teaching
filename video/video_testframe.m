function img = video_testframe(h, w, kind, k)
%VIDEO_TESTFRAME  生成测试视频帧 (可复现, 用于纯软件验证与压缩率标定)
%
%   输入:
%     h, w  : 图像高、宽 (默认 240, 320)
%     kind  : 内容类型
%               'simple'  - 平滑渐变 + 若干平坦块 (细节最少, JPEG 最小)
%               'complex' - 叠加高频纹理 (细节多, 接近真实视频)
%               'moving'  - 带平移的结构化图案, 随帧号 k 运动 (最接近真实视频)
%     k     : 帧序号 (仅 'moving' 使用, 默认 1)
%
%   说明: 内容复杂度强烈影响 JPEG 单帧字节数, 这是吞吐预算的关键不确定项。
%         本函数提供 3 档复杂度, 用于给出压缩率的【区间】而非单点估计。

if nargin < 1 || isempty(h), h = 240; end
if nargin < 2 || isempty(w), w = 320; end
if nargin < 3 || isempty(kind), kind = 'moving'; end
if nargin < 4 || isempty(k), k = 1; end

[X, Y] = meshgrid(linspace(0, 1, w), linspace(0, 1, h));
v = 128 + 40*(X - 0.5);

switch lower(kind)
    case 'simple'
        % 平坦块 + 一个竖直边缘
        v(X > 0.55 & Y > 0.5)   = 200;
        v(X < 0.30 & Y < 0.35)  = 45;
        v(abs(X - 0.5) < 0.012) = 235;

    case 'complex'
        % 高频纹理 (棋盘 + 细栅格) => 压缩率差, 代表高细节画面
        v = v + 30*sign(sin(60*pi*X) .* sin(60*pi*Y));
        v = v + 20*sin(160*pi*X) .* cos(140*pi*Y);
        v(X > 0.55 & Y > 0.5) = 200;

    case 'moving'
        % 平移的圆盘 + 移动条纹 (模拟运动) => 接近真实视频
        x0 = 0.2 + 0.6*mod(k-1, 40)/40;        % 水平平移
        y0 = 0.5 + 0.15*sin(2*pi*mod(k-1,40)/40);
        r  = 0.12;
        v((X-x0).^2 + (Y-y0).^2 < r^2) = 230;
        v = v + 18*sign(sin(40*pi*(X - 0.01*mod(k-1,60))));   % 缓慢移动的条纹
        v(X > 0.85) = 60;                                       % 右侧暗边

    otherwise
        error('video_testframe:badKind', '未知类型: %s', kind);
end

img = uint8(max(0, min(255, v)));

end
