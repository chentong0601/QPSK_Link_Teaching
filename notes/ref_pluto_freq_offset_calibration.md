# 参考笔记：Pluto 频偏标定（Frequency Offset Calibration，Simulink）

> 来源: https://www.mathworks.cn/help/comm/plutoradio/ug/frequency-offset-calibration-with-adalm-pluto-radio-simulink.html
>      （镜站: https://www.mathworks.com/help/comm/plutoradio/ug/frequency-offset-calibration-with-adalm-pluto-radio-simulink.html）
> 整理日期: 2026-09-10 | 类型: 官方文档摘录 + 项目适配分析
> 关键词: 双板频偏标定、FFT 找峰、`plutoradiofreqcalib`、`findpeakfreq.m`
> **注意**: 这是 `ref_pluto_frequency_correction.md`（参考 #2）的**姊妹示例**，两者分工不同，见 §1。

---

## 1. 示例定位（与参考 #2 的分工）

用**两个 Simulink 模型**测定**两块 Pluto 之间**的相对频偏：

| 模型文件 | 显示名 | 角色 |
|---|---|---|
| `plutoradiofreqcalib` | Frequency Offset Calibration (Tx) with ADALM-PLUTO Radio | **发射**一个 **12000 Hz 正弦波** |
| `plutoradiofreqcalib_rx` | Frequency Offset Calibration (Rx) with ADALM-PLUTO Radio | **接收**、算频偏、显示 |

### ★ 与参考 #2 的关键区别

官方在本页**明确**写了一句分工说明：

> "This example deals with offset in the **center frequency only**.
> To compensate for offsets in **both** the center frequency and the baseband sample rate,
> see the `FrequencyCorrectionForADALMPLUTORadioExample`."

即：

| 维度 | **#2 频率校正**（Frequency Correction） | **#3 频偏标定**（本页） |
|---|---|---|
| 修正对象 | 中心频率 **+ 基带采样率** | **仅**中心频率 |
| 修正手段 | `FrequencyCorrection` 参数（ppm） | **手动改** RX 中心频率 |
| 测量信号 | **三音** 20 / 40 / 80 kHz（用 80 kHz 估计） | **单音 12 kHz** |
| 测量方法 | 音调频率反推 K → ppm | **FFT 找峰** |
| 输出单位 | **ppm** | **Hz** |
| 自动化程度 | 算出 ppm 写入参数 | **人工闭环**（读数→手改→再验证） |

> 一句话：**#3 = 怎么把频偏"量"出来（含人工补偿流程）；#2 = 怎么把它"算成 ppm 并写进硬件"。**
> 两者互补，双板实验建议先用 #3 量，再用 #2 固化。

---

## 2. 原理：FFT 找峰

### 2.1 接收模型的输出（三项）

1. **频偏的定量数值**
2. 接收机**无杂散动态范围（SFDR）的图形视图**
3. 接收信号**定性 SNR 的图形视图**

（后两项与参考 #1 的频谱分析示例同源）

### 2.2 接收子系统结构

接收子系统含两个关键模块：

| 模块 | 作用 |
|---|---|
| **Find Peak Frequency** | 用 FFT 找接收信号中**功率最大**的频率 |
| **Spectrum Analyzer** | 计算并显示接收信号的**功率谱密度（PSD）** |

**Find Peak Frequency 子系统**内部：
- `Periodogram` 模块 → 输出接收信号的 PSD 估计
- `Probe` 模块 → 取出**帧长（FrameSize）**与**帧采样时间（FrameSampleTime）**
- 据两者找到整个频段内**幅度最大值的索引**，再按下式把索引换算成频率：

```
Foffset = IndexofMaxAmplitude * FrameSize / (FFTLength * FrameSampleTime)
```

（该换算由 MATLAB 函数 **`findpeakfreq.m`** 完成）

**化简理解**：当 `FrameSampleTime` 取帧周期（= FrameSize/SampleRate）时，

```
Foffset = Index × SampleRate / FFTLength  =  峰值谱线号 × 频率分辨率
```

即：**找到 PSD 的最大谱线，用"谱线号 × 频率分辨率"得到它落在哪个频率上**。

### 2.3 从"峰值频率"到"频偏"

官方原文：

> "the frequency with the maximum power in the received signal, **which equals the
> frequency offset plus 12000 Hz**"

所以：

```
频偏 = 峰值频率 − 12000 Hz
```

**官方给出的示例结果**：
- 峰值在约 **7 kHz** → 频偏 ≈ **7 − 12 = −5 kHz**
- 接收机 SFDR ≈ **34 dB**
- 频谱显示范围 −50 kHz ~ +50 kHz

---

## 3. 完整标定流程（官方步骤）

```
1. 连接两块 ADALM-PLUTO 到电脑
2. 运行发射模型  plutoradiofreqcalib           （持续发 12000 Hz 正弦）
3. 打开接收模型  plutoradiofreqcalib_rx
4. ★ 把接收模型里 "ADALM-PLUTO Radio Receiver" 模块的
     Center frequency 设成与发射模型**相同**的中心频率
5. 运行接收模型 → 仿真过程中实时算出并显示频偏
6. ★ 补偿: 把显示的频偏值**加到** RX 模块的中心频率上
     若频偏为负 → 则从中**减去**
7. ★ 验证: 补偿后频谱的最大值应落在 12000 Hz
```

**注意第 4 步和第 6 步是一对**：
先让收发中心频率设成一样（此时残差就是纯频偏），
再把测出的频偏加回 RX 中心频率 → 让接收 LO 实际落到发射 LO 上。

---

## 4. 对本项目的价值与适配 ★

### 4.1 ★ 提供了第二种独立的频偏测量法 → 可交叉验证

本项目目前测频偏用的是 **前导首尾分段相位差法**（`sync/freq_sync.m`）。
本示例用的是 **单音 + FFT 找峰**。**两者原理完全独立**：

| 方法 | 原理 | 本项目现状 |
|---|---|---|
| 相位差法 | 去调制后首尾两段相位差 | ✅ 已实现（W2） |
| FFT 找峰 | PSD 峰值谱线号 × 分辨率 | ❌ 未实现 |

**两种独立方法测同一物理量，结果互相印证 → 是报告里很硬的验证证据。**
建议补一个小脚本：发单音 → 收 → FFT 找峰测频偏 → 与相位差法结果对比。

### 4.2 ★ 双板实验的"最简第一步"

参考 #2 的结论是：双板频偏可能**超出我们估计器 ±5208 Hz 的量程**。
本示例给了一个**比 ppm 校正更简单**的落地路径：

```
测出频偏（Hz） → 直接改 RX 的中心频率 → 让残差落进量程
```

即"H**z 域粗调**"路线，不需要算 ppm、不需要碰 `FrequencyCorrection` 参数。
**双板实验建议顺序**：
1. 先用本示例的**单音 FFT 找峰**测出 Δf（Hz）
2. 按 §3 第 6 步**改 RX 中心频率**，把 Δf 压到千赫兹以内
3. 再跑本项目的 QPSK 帧收发，让 `freq_sync` 做精细补偿

### 4.3 △ 值得注意的巧合：示例的频偏量级正好卡在我们量程边界

本示例测出的频偏约 **−5 kHz（幅度 5 kHz）**；
而本项目估计器的无模糊上限是

```
estRange = Rs / (2 × centerGap) = 250000 / 48 = 5208 Hz
```

**|−5 kHz| ≈ 5000 Hz 与 5208 Hz 几乎相等**——这个示例的典型双板频偏，
**正好落在我们估计器的边界上**。

（这个结论**不依赖**示例的中心频率取值，因为比较的是绝对 Hz 量级。
它进一步印证参考 #2 §4.2 的判断：**双板场景下我们的量程余量非常薄，
不做硬件粗校正就是赌博**。）

### 4.4 与本项目已有脚本的关系

本项目（含前一个工程）已有**单音收发**脚本：
`PlutoSDR_Wireless_Transceiver/main_stage3_tone.m`（2.4 GHz 单音，频谱峰命中 +100 kHz）。

本示例相当于它的 **Simulink 正式版 + 频偏定量化**：
我们当时是"看频谱峰在不在预期位置"，本示例是"**把峰值换算成数值、再反推频偏**"。
**升级点很明确：加上"找峰 + 换算 + 减标称"三步，脚本就变成频偏标定工具。**

### 4.5 可引用的参考数值

- Pluto 接收机 **SFDR ≈ 34 dB**（官方示例实测）
  → 报告里可作为"接收动态范围"的量级参照，与我们自己的增益扫描结果对照

---

## 5. 坑与注意事项

| # | 坑 | 说明 |
|---|---|---|
| 1 | **需要两块 Pluto** | 单板测不了"相对频偏"（本项目目前只有一块） |
| 2 | 模型名易混 | 两个模型 `plutoradiofreqcalib` / `plutoradiofreqcalib_rx`，别只下载一个 |
| 3 | **公式变量名有误导性** | 公式左边写作 `Foffset`，但实际算的是**峰值频率**（不是频偏）；真正的频偏要**再减 12000 Hz** |
| 4 | 只修中心频率 | **不处理基带采样率失配** → 长时间/长帧仍会有定时漂移（需参考 #2 或 W7 Gardner） |
| 5 | 人工闭环 | 补偿要手动改参数、再手动验证，不适合自动化流程 |
| 6 | 第 4 步易漏 | 忘了把 RX 中心频率设成与 TX 相同，测出来的就不是"相对频偏" |
| 7 | 中文站访问不稳定 | 本次抓取 `ww2.mathworks.cn` 返回了安全验证页，**英文站 `www.mathworks.com` 正常** → 以后中文站抓不到就换英文站 |

---

## 6. 行动项

- [ ] 写一个小脚本：**单音 → FFT 找峰 → 算频偏**，与 `freq_sync` 相位差法结果**交叉验证**（§4.1）
- [ ] 把该工具作为**双板实验的第一步**（Hz 域粗调），先于 QPSK 链路（§4.2）
- [ ] 报告引用"双板典型频偏 ≈ 5 kHz ≈ 估计器量程边界"这一判断，论证硬件粗校正是必需的（§4.3）
- [ ] 报告可引用 **SFDR ≈ 34 dB** 作为 Pluto 接收动态范围的量级参照（§4.5）
- [ ] 后续抓 MathWorks 文档时，中文站失败则改用英文站
