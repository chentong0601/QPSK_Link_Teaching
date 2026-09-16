function S = slice_budget(p, target, varargin)
%SLICE_BUDGET  分片预算: 由【空口单传输帧成功率】推算可用的视频参数
%
%   核心关系 (空口设计的关键约束):
%     一个视频帧需要 N 个传输帧【全部到齐】才能解码 (JPEG 不支持部分解码),
%     故   视频帧完成率  P = p^N
%          最大可接受片数 N_max = floor( log(target) / log(p) )
%   其中 p = 单个传输帧的空口成功率, target = 期望的视频帧完成率。
%
%   输入:
%     p      : 单传输帧成功率 (0~1)。由 main_p6_link_test.m 实测
%     target : 期望的视频帧完成率 (默认 0.5)
%     'SlicesForRes', [h w q; ...] : 计算各配置的片数与完成率
%     'ref'                        : 打印 p 的敏感性参考表
%   输出:
%     S.maxSlices : 满足 target 的最大片数
%     S.table     : (可选) 各配置的片数/完成率/PSNR 表
%
%   用法:
%     slice_budget(0.99, 0.5, 'SlicesForRes', [144 176 50; 120 160 50], 'ref')

if nargin < 2 || isempty(target), target = 0.5; end

% --- 解析可选参数 ---
cfgList = [];  showRef = false;
k = 1;
while k <= numel(varargin)
    a = varargin{k};
    if ischar(a) && strcmpi(a, 'SlicesForRes') && k < numel(varargin)
        cfgList = varargin{k+1};  k = k + 2;
    elseif ischar(a) && strcmpi(a, 'ref')
        showRef = true;  k = k + 1;
    else
        k = k + 1;
    end
end

S.p = p;  S.target = target;

if p <= 0 || p > 1
    error('slice_budget:badP', 'p 必须在 (0,1] 内');
end
if p >= 1
    S.maxSlices = inf;
else
    S.maxSlices = floor(log(target) / log(p));
end

% --- 各配置估算 ---
S.table = [];
if ~isempty(cfgList)
    n = size(cfgList,1);
    h = zeros(n,1); w = zeros(n,1); q = zeros(n,1);
    nsl = zeros(n,1); pc = zeros(n,1); ps = zeros(n,1);
    for i = 1:n
        h(i) = cfgList(i,1); w(i) = cfgList(i,2); q(i) = cfgList(i,3);
        img = imresize(video_testframe(240, 320, 'moving', 7), [h(i) w(i)]);
        jb  = jpeg_encode(img, q(i));
        [~, info] = video_slicer(jb, 1);
        nsl(i) = info.totalSlices;
        pc(i)  = p^nsl(i);
        ps(i)  = psnr8(img, jpeg_decode(jb));
    end
    S.table = [h w q nsl pc ps];
end

% --- 打印主结论 ---
fprintf('\n===== 分片预算 (单帧成功率 p = %.4f) =====\n', p);
fprintf('目标视频帧完成率 = %.0f%%\n', target*100);
if isinf(S.maxSlices)
    fprintf('p = 1  =>  片数不受限\n');
else
    fprintf('=> 最大可接受片数 N_max = %d  (每视频帧 ≤ %d 字节)\n', ...
            S.maxSlices, S.maxSlices*58);
end

if ~isempty(S.table)
    fprintf('\n各配置估算 (内容 moving, 最接近真实视频):\n');
    fprintf('%10s | %6s | %8s | %10s | %10s | %s\n', ...
            '分辨率','质量','片数','完成率','PSNR(dB)','判定');
    fprintf('%s\n', repmat('-',1,66));
    for i = 1:size(S.table,1)
        mark = '不可用';
        if S.table(i,4) <= S.maxSlices, mark = '<= 可用'; end
        fprintf('%5dx%-5d | %6d | %8d | %9.1f%% | %10.2f | %s\n', ...
            S.table(i,2), S.table(i,1), S.table(i,3), S.table(i,4), ...
            S.table(i,5)*100, S.table(i,6), mark);
    end
end

% --- 敏感性参考表 ---
if showRef
    fprintf('\n参考: 不同 p 与片数下的视频帧完成率\n');
    Ns = [12 24 36 48 96];
    fprintf('%10s |','片数 N');  fprintf('%9d', Ns);  fprintf('\n');
    fprintf('%s\n', repmat('-',1,58));
    for pp = [0.95 0.98 0.99 0.995 0.999]
        fprintf('%10.3f |', pp);
        for N = Ns, fprintf('%8.1f%%', pp^N*100); end
        fprintf('\n');
    end
end
fprintf('\n');

end

function p = psnr8(a, b)
    a = double(a); b = double(b);
    if ~isequal(size(a), size(b)), p = NaN; return; end
    mse = mean((a(:)-b(:)).^2);
    if mse == 0, p = Inf; else, p = 10*log10(255^2/mse); end
end
