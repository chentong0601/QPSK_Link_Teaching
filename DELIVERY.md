# 项目交付清单 — QPSK 空口链路

> 项目：基于 ADALM-Pluto 的低空无人机遥测 QPSK 链路设计与实现
> 状态：**已完成**（主线全部打通，含真实空口实测）

---

## 一、交付物总览

### 1. 代码（全部可运行）

| 类别 | 文件 | 功能 |
|---|---|---|
| **发射** | `transmitter/tx_frame.m` | 组帧（前导+帧头+payload） |
| | `transmitter/tx_baseband.m` | 上采样 + RRC 成形 |
| | `transmitter/gen_frame_sequences.m` | 收发共享序列（前导/扰码） |
| | `transmitter/content_encode.m` | 内容编码（文字/遥测/图像） |
| **接收** | `receiver/rx_frame.m` | 完整接收链（检测+频偏+相位校正+解调） |
| | `receiver/rx_baseband.m` | 匹配滤波 + 抽样 + 判决 |
| | `receiver/content_decode.m` | 内容还原 |
| **同步** | `sync/frame_detect.m` | 帧检测（**归一化**滑动相关，固定门限） |
| | `sync/freq_sync.m` | 频偏估计（相位差法） |
| **接收机** | `receiver/rx_receiver.m` | **连续接收状态机**（滑动缓冲，持续解帧） |
| **主脚本** | `main_w1_frame.m` | W1 帧结构验证 |
| | `main_w2_rx_sync.m` | W2 仿真全链路 |
| | `main_w2_scan.m` | W2 频偏/SNR 扫描 |
| | `main_w3_overair.m` | W3 真实空口收发 |
| | `main_w4_content.m` | W4 多内容源 |
| | `main_w5_measure.m` | W5 硬件实测（增益扫描） |
| | `main_w6_receiver.m` | **W6 连续接收（20帧+频偏）** |
| | `main_w6_sweep.m` | **W6 灵敏度扫描** |
| | `main_demo.m` | **一键演示** |

### 2. 文档

| 文件 | 内容 |
|---|---|
| **`notes/ref_INDEX.md`** | **★ 参考资料索引（外部文档统一入口）** |
| **`notes/spec_for_review.md`** | **★ 方案说明书（评审版）：方案/内容/流程/指标/呈现/GUI决策** |
| **`notes/exp_baseline_metrics.md`** | **★ 实测基线指标（含对评审发现问题的核对与修正）** |
| **`notes/exp_w7_solution_study.md`** | **★ W7 方案裁决：4 个实验链，选定 DD-PLL（12dB 35%→100%，零带宽代价）** |
| **`notes/plan_w7_and_simulink.md`** | **★ W7 方案 + Simulink 定位（设计决策文档）** |
| `notes/design.md` | 设计文档（可演化为开题报告） |
| `notes/report_draft.md` | **项目报告**（含全部实测数据） |
| `notes/research_github.md` | GitHub 同类项目调研（W2） |
| **`notes/research_github_w7.md`** | **★ GitHub 调研（W7 定时同步/相位跟踪，含可参照代码）** |
| `notes/w3_run_tutorial.md` | W3 运行教程 |
| `notes/stage_w6_receiver.md` | **W6 连续接收机笔记（归一化相关原理+踩坑）** |
| **`notes/stage_w7_sync_tracking.md`** | **★ W7b DD-PLL 相位跟踪（集成与验收，12dB 35%→100%）** |
| **`notes/exp_w7a_timing_decision.md`** | **★ W7a 决策记录（定时误差量化后决定不实现）** |
| **`notes/stage_w7_sync_tracking.md`** | **★ W7b DD-PLL（12dB 35%→100%，BER 贴合理论）** |
| **`notes/exp_baseline_metrics.md`** | **★ 实测基线（评审核对与修正依据）** |
| `notes/ref_matlab_spectral_analysis.md` | **参考笔记：MathWorks 频谱分析示例（DC 去除/频谱仪用法）** |
| `notes/ref_pluto_frequency_correction.md` | **参考笔记：Pluto 频率校正（ppm / 双板同步 / 分级校正架构）** |
| `notes/ref_pluto_freq_offset_calibration.md` | **参考笔记：Pluto 频偏标定（单音 FFT 找峰 / Hz 域粗调）** |
| `README.md` | 工程说明 + 进度 |

### 3. 数据与图

| 文件 | 内容 |
|---|---|
| `results/w3_rxData.mat` | 真实空口接收数据 |
| `results/w5_measure.mat` | 增益扫描实测数据 |
| `plots/w2_freq_compensation.png` | 频偏补偿效果（报告核心图） |
| `plots/w4_image_transfer.png` | 图像传输对比 |
| `plots/w5_measure.png` | 增益扫描结果 |
| `plots/w6_sensitivity.png` | **连续接收灵敏度曲线** |
| `plots/w6_frame_success.png` | **解帧成功率 vs Eb/N0（短/满载荷对比，修正版）** |
| **`plots/w7_compare.png`** | **★ W6 vs W7 对比（解帧成功率 + BER 贴合理论）** |
| `plots/w7_pll_tracking.png` | **DD-PLL 相位跟踪轨迹** |

---

## 二、运行指南

### 环境要求
- MATLAB R2024b + ADALM-Pluto Support Package
- ADALM-Pluto 硬件（TX/RX 各装天线）
- 所有脚本在**工程根目录**运行

### 快速验证（纯仿真，无需硬件）
```matlab
main_w1_frame      % 帧结构
main_w2_rx_sync    % 仿真全链路 (应输出 PASS)
main_w4_content    % 多内容源 (应输出 3 个 PASS)
main_w6_receiver   % 连续接收机 (20帧, 应输出 20/20 PASS)
main_w6_sweep      % 灵敏度曲线 (Eb/N0=2dB 起 100%)
```

### 硬件运行（需 MATLAB GUI）
```matlab
main_w3_overair    % 真实空口收发 (应输出 [PASS] 真实空口成功!)
main_w5_measure    % 硬件实测数据采集
main_demo          % 一键演示
```

---

## 三、成果指标

| 指标 | 数值 |
|---|---|
| 调制方式 | QPSK (2 bit/符号) |
| 符号率 / 采样率 | 250 kSps / 1 MHz |
| 载波频率 | 2.4 GHz |
| 帧长 | 296 符号（前导32+帧头16+payload248）|
| 有效数据率 | ≈ 445 kbps |
| 真实空口结果 | 文字完整还原，频偏 -82.2±4.5 Hz |
| 图像传输 | 像素错误率 0% |
| **连续接收** | **20/20 帧（320 Hz 频偏下）** |
| **接收机灵敏度** | **Eb/N0 ≈ 2 dB（100% 解帧率）** |

---

## 四、演示流程（现场）

1. 运行 `main_demo`
2. 观察输出：组帧 → 发射 → 接收 → 还原消息
3. 展示演示图：**实时星座图**（蓝点收敛到红圈）+ **帧检测相关峰**
4. 展示 `main_w6_receiver`：20 帧连续解出、帧号 0→19 递增（"接收机在工作"）
5. 可选互动：修改 `msg` 内容重跑；拉远天线看何时失败

---

## 五、技术亮点（报告价值）

1. **完整链路**：从内容编码到真实空口收发，覆盖通信系统全环节
2. **同步算法**：帧检测（滑动相关）+ 频偏估计（相位差法），含理论推导
3. **关键发现**：识别并解决**空口公共相位问题**（QPSK 4 重模糊），仿真不暴露、真实系统必现
4. **实测数据**：增益扫描 + 稳定性测试，量化验证算法可靠
5. **工程方法**：离线数据分析法（保存 rxData 反复调试），避免重复硬件实验
6. **连续接收机**：归一化相关帧检测（门限与信号幅度无关）+ 滑动缓冲状态机，
   实现 20 帧连续无丢失解调，并给出灵敏度曲线（2 dB 门槛）
   —— 满足"通信接收机需持续工作"的课程要求
