function tab_overview(parent, projRoot)
%TAB_OVERVIEW  实验总览 Tab —— 18 个实验的状态与关键结果 (纯展示, 无回调)
%
%   数据为项目已完成实验的汇总指标 (来源: 博士课程-无线/ 下 6 份报告)
%   注: 只用 uilabel / uipanel / uitable / uigridlayout 的稳妥属性;
%       uigridlayout 不设 BackgroundColor (避免属性不支持), 靠父容器底色

    T = gui_theme();

    g = uigridlayout(parent, [3 1], 'RowHeight', {92, '1x', 34}, ...
                     'Padding', [14 14 14 14], 'RowSpacing', 10);

    %% ===== 顶部: 4 个亮点指标卡片 =====
    kpi = { ...
        '视频还原 PSNR', '36.76 dB', '空口实测 (仿真 37.70 dB)', T.ok; ...
        '物理层误码率',  '1.3e-5',   '952 帧 / 99.79% 字节正确',  T.primary; ...
        '实验完成度',    '18 / 18',  'W1~W7 + P0/P1/P2/E3/P5/P6', T.primary; ...
        '最佳接收增益',  '10 dB',    'P1 公网接收增益扫描最优',   T.warn };

    gKpi = uigridlayout(g, [1 4], 'ColumnWidth', {'1x','1x','1x','1x'}, ...
                        'Padding', [0 0 0 0], 'ColumnSpacing', 10);
    for i = 1:4
        p = uipanel(gKpi, 'BackgroundColor', T.card);
        gl = uigridlayout(p, [3 1], 'RowHeight', {'fit','fit','fit'}, ...
                          'Padding', [12 10 12 10], 'RowSpacing', 3);
        uilabel(gl, 'Text', kpi{i,1}, 'FontSize', T.fsSmall, 'FontColor', T.textSub);
        uilabel(gl, 'Text', kpi{i,2}, 'FontSize', T.fsBig, 'FontWeight', 'bold', ...
                'FontColor', kpi{i,4});
        uilabel(gl, 'Text', kpi{i,3}, 'FontSize', T.fsSmall, ...
                'FontColor', T.textSub, 'WordWrap', 'on');
    end

    %% ===== 中部: 实验清单表 =====
    pTab = uipanel(g, 'Title', '实验清单 (18 / 18 已完成)', ...
                   'FontSize', T.fsHead, 'BackgroundColor', T.card);
    glT = uigridlayout(pTab, [1 1], 'Padding', [8 8 8 8]);

    data = {
        'W1', '帧结构 + 波形生成',           '已完成',     '296 符号/帧, 1208 采样/帧';
        'W2', '频偏估计与纠正',              '已完成',     'FFT 扫频找峰, 残余 < 1 Hz';
        'W3', 'Pluto 单音 TX/RX (真实空口)', '已完成',     '星座四点清晰; 还原 HELLO QPSK!';
        'W4', '多内容源 (遥测 / 图像)',      '已完成',     '图像分块传输 3 x PASS';
        'W5', '链路实测',                    '已完成',     '实测频偏 -82.2 +/- 4.5 Hz';
        'W6', '连续接收机 (归一化相关)',     '已完成',     '20/20 帧 @ 320 Hz 频偏';
        'W7', 'DD-PLL 判决导向相位跟踪',     '已完成',     '8 dB BER 1.6e-4 (理论 1.9e-4)';
        'W7a','定时精调 (TED + 插值)',       '评估后不做', '残余定时误差 0.06T, 收益低';
        'P0', '环境确认 (JPEG 编解码)',      '已完成',     'imwrite/imread 路线, 5.3 ms/帧';
        'P1', '公网信号接收 (保底功能)',     '已完成',     'WiFi ch6 @2437 MHz; 诊断 ADC 饱和';
        'P2', '视频分片链路 (4B 分片头)',    '已完成',     '比特级完全一致; 6/6 鲁棒性通过';
        'E3', '视频参数权衡',                '已完成',     '三档模式 (均衡 176x144 @16.9 fps)';
        'P3', 'DD-PLL 集成进接收机',         '已完成',     '10 dB 解帧率 35% -> 100%';
        'P5', '端到端联调 (视频 over QPSK)', '已完成',     '视频 10/10, PSNR 37.70 dB';
        'P6a','空口链路质量评估',            '已完成',     '三个 RxGain 全部 p = 1.0000';
        'P6b','空口视频传输',                '已完成',     '视频 19/20, PSNR 36.76 dB';
        'BS', 'SNR x p 边界扫描',            '已完成',     '悬崖效应: p 1.0->0.945 时完成率 100%->7%';
        'RS', '全链路回归测试',              '已完成',     'W1/W2/W4/W6/P2/E3/P5 全 PASS' };

    uitable(glT, 'Data', data, ...
            'ColumnName', {'编号', '实验内容', '状态', '关键结果'}, ...
            'ColumnWidth', {56, 238, 96, 'auto'}, 'RowName', {});

    %% ===== 底部: 数据来源说明 =====
    uilabel(g, 'Text', ['数据来源: 博士课程-无线/ 下 6 份实验报告 + results/ 下 31 个 .mat。' ...
                        '本 Tab 为静态汇总; 交互式数据分析见 Tab 3 数据体检。'], ...
            'FontSize', T.fsSmall, 'FontColor', T.textSub);
end