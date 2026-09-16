function s = tg_desc(fname)
%TG_DESC  成果图册 - 按文件名返回中文说明 (顶层函数)
%
%   用 contains 做子串匹配, 顺序敏感: 更具体的匹配放前面
    if contains(fname, 'p6_overair_video')
        s = 'P6 空口视频还原 —— 19/20 帧, PSNR 36.76 dB (仿真 37.70), 误码率 1.3e-5; 同轴短线 + RxGain 30 dB';
    elseif contains(fname, 'p5_e2e_video')
        s = 'P5 端到端联调 —— 视频 over QPSK: 10/10 帧还原, PSNR 37.70 dB, 等效 16.3 fps';
    elseif contains(fname, 'w3_overair_constellation')
        s = 'W3 真实空口星座图 —— QPSK 四点清晰可分; 帧内相位斜坡 25.3 度被 DD-PLL 跟住';
    elseif contains(fname, 'w3_diag_constellation')
        s = 'W3 诊断星座图 —— 未做频偏纠正时的星座旋转';
    elseif contains(fname, 'w3_symbol_error')
        s = 'W3 符号误差 —— 逐符号误差向量';
    elseif contains(fname, 'w3_symbol_compare')
        s = 'W3 收发符号对比 —— 逐符号一致性';
    elseif contains(fname, 'w7_pll_tracking')
        s = 'W7 DD-PLL 相位跟踪 —— 真实空口的帧内相位斜坡被完整跟踪';
    elseif contains(fname, 'w7_compare')
        s = 'W7 对比 —— W6 (无 PLL) vs W7 (有 PLL) 的解帧率与 BER, 等效增益约 6 dB';
    elseif contains(fname, 'w6_sensitivity')
        s = 'W6 灵敏度 —— 解帧率 vs Eb/N0, 灵敏度 Eb/N0 约 2 dB';
    elseif contains(fname, 'w6_frame_success')
        s = 'W6 帧成功率 —— 归一化相关 (门限 0.60), 20/20 帧 @ 320 Hz 频偏';
    elseif contains(fname, 'w5_measure')
        s = 'W5 链路实测 —— 实测频偏 -82.2 +/- 4.5 Hz';
    elseif contains(fname, 'w2_freq_compensation')
        s = 'W2 频偏纠正 —— FFT 扫频找峰 + 相位补偿前后对比';
    elseif contains(fname, 'w1_frame_waveform')
        s = 'W1 帧波形 —— 前导 + 数据段, 296 符号 / 1208 采样';
    elseif contains(fname, 'w4_image_transfer')
        s = 'W4 图像传输 —— 图像分块 over QPSK, 3 x PASS';
    elseif contains(fname, 'e3_video_tradeoff')
        s = 'E3 视频参数权衡 —— 分辨率/质量 vs 帧率/PSNR; 内容复杂度主导 (差 6~7 倍)';
    elseif contains(fname, 'boundary_scan')
        s = '边界扫描 —— 揭示悬崖效应: Eb/N0 8->6 dB 时 p 从 1.0 跌到 0.945, 视频完成率 100%->7%';
    elseif contains(fname, 'p1_gain_sweep')
        s = 'P1 增益扫描 —— 4 档 RxGain (30/23/10/0): 噪声底单调降 54.9 dB, 最佳工作点 10 dB';
    elseif contains(fname, 'p1_public_signal_WiFi')
        s = 'P1 公网信号 (WiFi ch6 @2437 MHz) —— 收到 -5.1 dBFS; IQ 散点呈方形 = ADC 削顶';
    elseif contains(fname, 'p1_public_signal_GSM')
        s = 'P1 公网信号 (GSM900) —— TDMA 突发, 占空比 ~12.5%';
    elseif contains(fname, 'p1_public_signal_LTE')
        s = 'P1 公网信号 (LTE) —— OFDM 连续谱, 噪声状';
    elseif contains(fname, 'p1_public_signal_LockedFc')
        s = 'P1 锁定频点后的公网信号详细分析';
    elseif contains(fname, 'diag_p6_rxwave')
        s = 'P6 诊断 —— 接收波形 / 星座图';
    elseif contains(fname, 'demo_result')
        s = '综合演示 —— QPSK 链路端到端结果';
    else
        s = fname;
    end
end