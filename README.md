# QPSK_Link_Teaching — QPSK 空口链路教学旗舰工程

> 在纯仿真 QPSK 基带链路（已在 `PlutoSDR_Wireless_Transceiver` 完成阶段1~3）基础上，
> 用 ADALM-Pluto 实现 **真实空口 QPSK 帧收发**：帧结构 / 帧同步 / 频偏补偿 / 多内容传输。
> 定位：面向职业本科"动态避障与低空通信"课程的 SDR 教学演示系统。

## 与前一个工程的关系

```
PlutoSDR_Wireless_Transceiver   ← 已完成: 阶段1(符号级仿真)+阶段2(基带链路)+阶段3(单音硬件)
QPSK_Link_Teaching (本工程)     ← 复用其 tx_baseband/rx_baseband, 新增帧/同步/硬件闭环
```

## 当前进度：✅ 全部完成

| 阶段 | 内容 | 状态 | 产出 |
|---|---|---|---|
| W1 | 帧结构 + 发射端波形（纯仿真） | ✅ | `tx_frame.m` / `main_w1_frame.m` |
| W2 | 接收端同步算法（帧检测+频偏估计+解调） | ✅ | `sync/` + `rx_frame.m` + `main_w2_rx_sync.m` |
| W3 | Pluto 单板空口帧收发闭环 | ✅ | `main_w3_overair.m`（真实空口 "HELLO QPSK!" 还原） |
| W4 | 多内容源（文字/遥测/图像） | ✅ | `content_encode/decode.m` + `main_w4_content.m` |
| W5 | 报告初稿 + 运行教程 | ✅ | `notes/report_draft.md` / `notes/w3_run_tutorial.md` |
| W6 | **连续接收机（归一化相关帧检测 + 状态机）** | ✅ | `receiver/rx_receiver.m` + `main_w6_receiver.m` |
| W7 | **DD-PLL 相位跟踪 + 定时决策（W7a 量化否决）** | ✅ | `sync/phase_track.m` + `main_w7_compare.m` |
| W7a | 定时精调必要性评估（残留 0.06 T，决定不做） | ✅ | `main_w7a_timing_eval.m` + `notes/exp_w7a_timing_decision.md` |
| P1 | **公网信号接收（扫频 + PSD + ADC 饱和诊断）** | ✅ | `main_p1_public_signal.m` + 报告 |
| P5 | 端到端视频联调 + 实时性优化（135%→75.6%） | ✅ | `main_p5_e2e_video.m` |
| P6 | **真实空口联调（物理层 952/952，PSNR 36.76 dB）** | ✅ | `main_p6_link_test.m` / `main_p6_video_overair.m` |
| E4 | **四类内容业务 × 三链路（文字/图片/音频/视频）** | ✅ | `main_e4_*.m` + `experiments/e4_*.m` |

**关键成果**：

- 真实空口实测：帧成功率 **952/952**，载荷字节正确率 **99.79%**，误码率 ≈ 1.3×10⁻⁵
- 视频实时收发：空口 **20 帧还原 19 帧，PSNR 36.76 dB**（较仿真仅差 0.94 dB）
- 四类内容业务（文字/图片/音频/视频）在同轴、5 cm 短天线、10 cm 长天线三种链路下**全部达标**
- 公网信号接收：WiFi ch6 / GSM900 / LTE Band 3 频谱特征清晰可辨；**定量诊断出 ADC 削顶**（边缘堆积比判据），确定最佳接收增益 10 dB
- 接收机性能评价：三链路 EVM 浴缸曲线，最优增益 25–30 dB，最优 EVM ≈ 10.4–10.7%
- 发现并修复空口解调关键问题：**QPSK 4 重相位模糊的公共相位校正**（仿真不暴露，空口必现）

## 技术路线（分层推进，每层验证后才上硬件）

```
L1 纯仿真       帧结构 + 发射波形（无噪声，验证帧成形正确）        ✅
L2 仿真+AWGN    帧检测 + 频偏补偿 + 解调（注入噪声/频偏验证）      ✅
L3 硬件闭环     Pluto 空口: 帧波形发射 → 天线 → 接收 → 同步 → 解调  ✅
L4 教学演示     多内容源 + 实测数据 + 报告                        ✅
```

## 目录结构

```
QPSK_Link_Teaching/
├── README.md
├── config/init_params.m           # 统一参数（帧结构 + Pluto 硬件参数）
├── transmitter/
│   ├── tx_baseband.m              # 发射基带: 上采样+RRC成形
│   ├── tx_frame.m                 # 组帧: 前导+帧头+payload
│   ├── gen_frame_sequences.m      # 收发共享序列(前导/扰码)
│   └── content_encode.m           # 内容源编码(文字/遥测/图像)
├── receiver/
│   ├── rx_baseband.m              # 接收基带: 匹配滤波+抽样+判决
│   ├── rx_frame.m                 # 完整接收链(检测+频偏+相位校正+解调)
│   ├── rx_receiver.m              # 连续接收状态机(滑动缓冲, W6)
│   └── content_decode.m           # 内容还原
├── sync/
│   ├── frame_detect.m             # 帧检测(归一化滑动相关, 固定门限)
│   ├── freq_sync.m                # 频偏估计(前导首尾分段相位差法)
│   ├── phase_track.m              # ★ DD-PLL 相位跟踪(W7b)
│   └── frame_sequences_cached.m   # 帧序列缓存(消除每帧重建+rng副作用)
├── video/                         # 视频应用层（实验3 新增）
│   ├── video_protocol.m           # 分片协议常量（唯一真源）
│   ├── jpeg_encode.m              # JPEG 编码（imwrite 路线）
│   ├── jpeg_decode.m              # JPEG 解码（imread 路线）
│   ├── video_slicer.m             # 视频帧 -> 传输帧载荷
│   ├── video_reassembler.m        # 状态机重组（丢帧/重复统计）
│   ├── video_testframe.m          # 三档复杂度测试帧
│   └── slice_budget.m             # ★ 分片预算(由 p 推算可用视频参数)
├── experiments/                   # 实验与诊断脚本
│   ├── rx_sanity_check.m          #   接收数据三步体检链
│   ├── plot_p1_gain_sweep.m       #   P1 增益扫描对照图
│   ├── e4_*.m                     #   四类业务实验与绘图
│   └── content_check.m            #   素材规格自检
├── notes/
│   ├── ref_INDEX.md               # ★ 参考资料索引（外部文档统一入口）
│   ├── spec_for_review.md         # ★ 方案说明书（评审版，可交外部审核）
│   ├── exp_baseline_metrics.md    # ★ 实测基线指标（评审核对/修正依据）
│   ├── exp_w7_solution_study.md   # ★ W7 方案裁决（4 个实验链, 选定 DD-PLL）
│   ├── plan_w7_and_simulink.md    # ★ W7 方案 + Simulink 定位（设计决策）
│   ├── design.md                  # 设计文档(可演化为开题报告)
│   ├── research_github.md         # GitHub 同类项目调研(W2)
│   ├── research_github_w7.md      # ★ GitHub 调研(W7 定时同步/相位跟踪)
│   ├── ref_matlab_spectral_analysis.md  # MathWorks 频谱分析示例(MATLAB+Simulink)
│   ├── ref_pluto_frequency_correction.md # Pluto 频率校正(ppm, 双板同步)
│   ├── ref_pluto_freq_offset_calibration.md # Pluto 频偏标定(Hz, FFT找峰)
│   ├── w3_run_tutorial.md         # W3 运行教程
│   ├── stage_w6_receiver.md       # W6 连续接收机笔记
│   ├── stage_w7_sync_tracking.md  # ★ W7b DD-PLL 相位跟踪(集成与验收)
│   ├── exp_w7a_timing_decision.md # ★ W7a 决策记录(量化后决定不做)
│   └── boundary_scan.m            # ★ SNR×p 边界扫描(验证 p≥0.99 阈值)
│   └── report_draft.md            # 项目报告初稿
├── main_w1_frame.m                # W1 主脚本
├── main_w2_rx_sync.m              # W2 主脚本(仿真全链路)
├── main_w2_scan.m                 # W2 频偏/SNR 扫描
├── main_w3_overair.m              # W3 主脚本(真实空口, 需GUI运行)
├── main_w4_content.m              # W4 主脚本(多内容源)
├── main_w5_measure.m              # W5 硬件实测(增益扫描+重复性, 需GUI)
├── main_w6_receiver.m             # W6 连续接收机(20帧 + 频偏)
├── main_w6_sweep.m                # W6 灵敏度扫描
├── main_w7_compare.m              # ★ W6 vs W7 对比(报告核心图)
├── main_w7a_timing_eval.m         # ★ 定时误差影响评估(W7a 决策依据)
├── main_p5_e2e_video.m            # ★ P5 端到端联调(视频 over QPSK)
├── main_p1_public_signal.m        # ★ P1 公网信号接收(扫频+PSD, 保底功能)
├── main_p6_link_test.m            # ★ P6a 空口链路质量评估(测单帧成功率 p)
├── main_p6_video_overair.m        # ★ P6b 空口视频传输(需 GUI + 硬件)
├── plots/                         # 成果图表（入库，可由脚本复现）
```

## 运行约定

- 主脚本在**工程根目录**运行，需 `addpath('config') ('transmitter') ('receiver') ('sync')`
- 硬件脚本（W3）必须在 **MATLAB GUI** 运行（`-batch` 不注册 Support Package 路径）
- RF 安全：TX 增益低起步(-20dB)，天线接好再发射

## 参考资料

外部文档/官方示例统一沉淀在 `notes/ref_*.md`，入口见 **`notes/ref_INDEX.md`**。
新增参考时请同步登记索引，并写明"对本项目的价值与适配"。

## 帧结构

```
| 前导 Preamble (32符号) | 帧头 Header (16符号=32bit) | payload (≤248符号=62字节) |
|←──────────────────── 296 符号 = 1 帧 ────────────────────→|
```
- **前导**：伪随机 QPSK 序列 → ①滑动相关找帧起点 ②估计载波频偏
- **帧头**：类型(2) + payload字节数(8) + 帧号(8) + 校验(8) + 保留(6)
- **payload**：内容字节（自动补零 + 加扰）

## 关键算法

| 模块 | 算法 | 说明 |
|---|---|---|
| 帧检测 | **归一化**滑动相关 ρ=\|C\|/√(E_r·E_p) | 门限与幅度无关，适合连续接收 |
| 频偏估计 | 前导首尾分段相位差法 | 去调制 + 相干平均 + 相位差 |
| 公共相位校正 | 前导估计残余常数相位 | **空口必需**（4重相位模糊） |
| 连续接收 | 滑动缓冲状态机 | 持续解帧、帧间自动消费 |
| 定时 | 固定抽样（d=0最优） | 单板场景足够；Gardner 为拓展项 |

## 环境要求

| 项 | 版本 / 说明 |
|---|---|
| MATLAB | R2024b（实测 24.2.0.2712019） |
| 工具箱 | Communications Toolbox、Signal Processing Toolbox、DSP System Toolbox、Instrument Control Toolbox |
| 硬件支持包 | Communications Toolbox Support Package for ADALM-Pluto Radio |
| 硬件 | ADALM-Pluto SDR（AD9363，325 MHz–3.8 GHz），USB 连接后网卡地址 `192.168.2.1` |
| 操作系统 | Windows 10/11（路径含中文亦可，脚本已用 `fullfile` 拼接） |

> 无硬件也可运行：W1/W2/W6 为纯仿真链路，`main_w1_frame.m`、`main_w2_rx_sync.m`
> 可直接跑通；涉及 `sdrtx/sdrrx` 的脚本需要 Pluto 在位。

## 快速开始

```matlab
% 1. 进入工程根目录（脚本均以根目录为工作路径）
cd QPSK_Link_Teaching

% 2. 加入路径（或直接运行主脚本，主脚本内部已 addpath）
addpath('config','transmitter','receiver','sync','video','experiments');

% 3. 纯仿真快速验证（无需硬件）——应与文档记录一致
main_w1_frame          % W1 帧结构与发射波形
main_w2_rx_sync        % W2 全链路仿真（帧检测 + 频偏补偿 + 解调）

% 4. 有硬件时（务必先接天线再发射，低功率起步）
main_w6_receiver       % 连续接收机
main_p6_link_test      % 空口链路质量（单帧成功率 p）
```

硬件脚本在 `-batch` 模式下通常可用；若遇到 Support Package 路径未注册，
改用 MATLAB 桌面环境运行。

## 数据可得性

**本仓库只包含可复用的工程代码与成果图，不含实验原始数据。**

原始采集数据（GB 级）与实验运行产物均保留在本地，未纳入版本库：

| 内容 | 本地位置 | 说明 |
|---|---|---|
| P1 公网信号采集 | `results/p1_public_*.mat` | 6 个权威数据集（增益 0/10/23/30 dB 对照 + LTE Band 3） |
| E4 四类业务结果 | `results/e4/` | sim / coax / short / long 四条件的收发对照与性能数据 |
| 业务素材本体 | `content/` | 照片、语音及其处理规格族 |

成果图（`plots/`）已入库，可由 `main_*.m` 脚本重新生成，无需原始数据即可查看结论。

### 为什么这些内容不入库

- **课程材料**：课程要求、实施方案与实验报告属个人课程交付，与工程本身无关
- **个人素材**：文字业务载荷含署名、语音素材文件名含居住地信息
- **大体积数据**：原始 IQ 采集为 GB 级，不适合版本控制

## 图表预览

| 图 | 位置 |
|---|---|
| 四类业务 × 四条件结果（文字/图片/音频/视频） | `plots/e4/` |
| 三链路 EVM 浴缸曲线 | `plots/e4/fig_evm_bathtub_*.png` |
| 天线耦合频率扫描对比 | `plots/e4/fig_antsweep_*.png` |
| 公网信号四频段频谱 | `plots/p1_public_signal_*.png` |
| 空口联调结果 | `plots/p6_overair_video.png` |
| 交互式成果展示页 | `index.html`（单页，浏览器直接打开） |

## 目录结构（补充）

```
QPSK_Link_Teaching/
├── content/
│   └── README.md                  # 素材规格与分片策略（素材本体不入库）
├── gui/                           # 成果展示台（sdr_showcase）
├── index.html                     # 交互式成果展示页（21 图）
└── plots/                         # 成果图表（入库，可由脚本复现）
```

## 许可

代码以 **MIT License** 发布，见 `LICENSE`。

## 引用

如本项目对你的工作有帮助，可参考：

```bibtex
@misc{fluuzugrzt2026qpsk,
  title  = {QPSK_Link_Teaching: QPSK over-the-air link with ADALM-Pluto},
  author = {fluuzugrzt},
  year   = {2026},
  note   = {MATLAB R2024b, ADALM-Pluto SDR}
}
```

## 已知限制与拓展方向

- 第二块 Pluto 暂缺 → 真实异源频偏实验待补（仿真已覆盖算法验证）
- 视频超链路容量（1.0 Mbps > 445 kbps）→ 用图像渐进传输替代
- 接收机尚未含 **符号定时同步（Gardner）** 与 **相位跟踪（PLL）** → W7 候选
- 可拓展：Gardner 定时恢复、CRC 自动重传、16QAM/OFDM
