# 参考笔记：Pluto 频率校正（Frequency Correction，Simulink）

> 来源: https://ww2.mathworks.cn/help/comm/plutoradio/ug/frequency-correction-for-adalm-pluto-radio-in-simulink.html
> 整理日期: 2026-09-10 | 类型: 官方文档摘录 + 项目适配分析
> 关键词: 双板同步、ppm、FrequencyCorrection、`plutoradioFrequencyCorrectionRx`

---

## 1. 示例定位

用 **ADALM-Pluto Radio Receiver 模块的 `Frequency correction` 参数**，
把**两块 Pluto** 的基带采样率与中心频率**硬件级对齐**。

**核心问题**：一个 Pluto 的基带采样率和中心频率**物理上来自同一个晶振**。
出厂校准会用 PLL 设置去数字补偿晶振的器件差异，但这个补偿**不完美**，因为：

1. **量化效应**（PLL 分频器只能取离散值）
2. **工作条件变化**（尤其是**温度**）

后果：**即使两块 Pluto 配置了相同的采样率与中心频率，实际工作频率仍略有不同。**

**解法**：用 `Frequency correction` 参数（单位 **ppm**）微调接收端的
基带采样率与中心频率。示例中把其中一块当"准确源"，用另一块测出的音调
频率反推校正值，最终把收到的音调拉回到发射的 **80 kHz**。

**对本项目的直接意义**：这正是我们在 W5 测得"单板稳定频偏 -82.2±4.5 Hz"
的物理根源所在，也是**双板实验的必备前置步骤**（见 §4）。

---

## 2. 原理与公式

### 2.1 符号定义

| 符号 | 含义 |
|---|---|
| `fc`, `fs` | **发射机**的中心频率、基带采样率 |
| `fc'`, `fs'` | **接收机**的中心频率、基带采样率 |
| `K` | 接收机晶振相对发射机的漂移因子，`fc' = K·fc`，`fs' = K·fs`，`K ≈ 1` |
| `fref` | 发射端基带音调频率（示例 80 kHz） |
| `freceived` | 接收端观测到的音调频率 |

### 2.2 接收频率公式

```
freceived = [ fref + (fc - K·fc) ] / K
```

**两项误差来源**（这是理解频偏的关键）：
- 分子 `(fc − K·fc)` —— **中心频率不匹配**（载波偏置）
- 分母 `K` —— **基带采样率不匹配**（采样率失配，导致基带频率整体缩放）

> 这一点很重要：真实频偏**同时包含载波偏置和采样率缩放**两个成分，
> 我们目前 W2/W6 的数字估计**只补了载波偏置**，采样率缩放没有处理。

### 2.3 求解 K

```
K = (fc + fref) / (fc + freceived)
```

### 2.4 求解校正量 p（ppm）

要让收发对齐，需把接收机的采样率与中心频率同乘 `1/K`。
设 ppm 校正量为 `p`，则 `1 + p/10^6 = 1/K`，得：

```
p = (freceived - fref) / (fc + fref) * 10^6
```

**数值验证**（用示例给出的数据）：

```
fc = 2.42e9, fref = 80000, freceived = 68038.6
p = (68038.6 - 80000) / (2.42e9 + 80000) * 1e6
  = -11961.4 / 2.42008e9 * 1e6
  = -4.9425 ppm      ← 与示例输出 -4.9426 一致 ✓
```

### 2.5 多次校正的叠加

连续施加 `p1`、`p2` 两次校正，等价于一次性施加：

```
p_total = p1 + p2 + p1·p2·10^(-6)
```

（`p1·p2·10^-6` 是高阶小量，ppm 量级下通常可忽略，但示例程序里保留了。）

---

## 3. 完整代码

### 3.1 建发射机 + 初次接收（未校正）

```matlab
% Set up parameters and signals
sampleRate = 200e3;
centerFreq = 2.42e9;
fRef = 80e3;
s1 = exp(1j*2*pi*20e3*[0:10000-1]'/sampleRate);  % 20 kHz
s2 = exp(1j*2*pi*40e3*[0:10000-1]'/sampleRate);  % 40 kHz
s3 = exp(1j*2*pi*fRef*[0:10000-1]'/sampleRate);  % 80 kHz
s = s1 + s2 + s3;
s = 0.6*s/max(abs(s)); % Scale signal to avoid clipping in the time domain

% Set up the transmitter
% Use the default value of 0 for FrequencyCorrection, which corresponds to
% the factory-calibrated condition
tx = sdrtx('Pluto', 'RadioID', 'usb:1', 'CenterFrequency', centerFreq, ...
           'BasebandSampleRate', sampleRate, 'Gain', 0, ...
           'ShowAdvancedProperties', true);
% Use the info method to show the actual values of various hardware-related
% properties
txRadioInfo = info(tx)
% Send signals
disp('Send 3 tones at 20, 40, and 80 kHz');
transmitRepeat(tx, s);

% Open the receiver model
open_system('plutoradioFrequencyCorrectionRx')

% Run the receiver. The detected frequency may be far from 80 kHz
disp('Running the receiver...');
sim('plutoradioFrequencyCorrectionRx')
disp(['The detected frequency is ' num2str(peakFreq/1000) ' kHz.']);
```

**关键点**：
- `RadioID = 'usb:1'` —— **两块板同时连接时用它指定具体是哪一块**（本项目双板实验必备）
- `Gain = 0`（示例用 0 dB 发射增益）
- `ShowAdvancedProperties = true` —— 暴露高级属性（含 `FrequencyCorrection`）
- `info(tx)` —— 读回硬件**实际值**，输出里可见 `FrequencyCorrection: 0`

**官方给出的运行输出**：

```
txRadioInfo = 
  struct with fields:
                     Status: 'Full information'
            CenterFrequency: 2.4200e+09
         BasebandSampleRate: 200000
                  SerialNum: '1000002355237309002300260902167028'
                       Gain: 0
       RadioFirmwareVersion: "0.30"
    ExpectedFirmwareVersion: "0.30"
            HardwareVersion: "A0"
        FrequencyCorrection: 0

Send 3 tones at 20, 40, and 80 kHz
## Waveform transmission has started successfully and will repeat indefinitely. 
## Call the release method to stop the transmission.
Running the receiver...
The detected frequency is 68.0386 kHz.        ← 未校正, 偏离 80 kHz 达 12 kHz
```

### 3.2 计算校正量

```matlab
additionalCorrection = (peakFreq - fRef) / (centerFreq + fRef) * 1e6;
```

### 3.3 应用校正量

```matlab
currentFrequencyCorrection = str2double( ...
    get_param('plutoradioFrequencyCorrectionRx/ADALM-Pluto Radio Receiver', ...
    'FrequencyCorrection'))

newFrequencyCorrection = currentFrequencyCorrection + additionalCorrection + ...
    currentFrequencyCorrection*additionalCorrection*1e-6

set_param('plutoradioFrequencyCorrectionRx/ADALM-Pluto Radio Receiver', ...
    'FrequencyCorrection',num2str(newFrequencyCorrection,'%.12f'))
```

**输出**：

```
currentFrequencyCorrection =  0
newFrequencyCorrection =  -4.9426
```

### 3.4 验证

```matlab
disp('Running the receiver again...');
sim('plutoradioFrequencyCorrectionRx')
disp(['The detected frequency is ' num2str(peakFreq/1000) ' kHz.']);

% Release the transmitter radio
release(tx);
```

**输出**：

```
Running the receiver again...
The detected frequency is 80.04 kHz.      ← 校正后, 误差仅 40 Hz
```

---

## 4. 对本项目的价值与适配 ★

### 4.1 给我们 W5 实测的频偏换一个"标准单位"

W5 实测结果：**-82.2 ± 4.5 Hz**（2.4 GHz，单板环路）。

套用本示例的公式（`fref << fc`，故近似 `p ≈ Δf/fc × 10^6`）：

```
p = -82.2 / 2.4e9 * 1e6 = -0.0343 ppm
```

**这个数字非常小**（不到 0.04 ppm），说明该板出厂校准残差很小。
报告里用 **ppm** 表述比用 Hz 更专业、也更有可比性（可与厂家规格对照）。

> ⚠️ 但要谨慎下结论：W2 扫描显示我们的**估计器本身有负偏置**
> （注入 0 Hz 时，Eb/N0=12 dB 下估出 -7.8 Hz；0 dB 下估出 -49.2 Hz，
> 且偏置随 SNR 降低而增大）。所以 -82.2 Hz 里**混有估计器偏置**，
> 不能全部归因于硬件。报告里应写成"
> 实测等效频偏约 0.03 ppm（含估计器偏置，偏置量级见 W2 扫描）"。

### 4.2 ★ 关键发现：双板实验的频偏会**超出我们估计器的量程**

示例那块接收板的误差是 **-4.9426 ppm**。换算成 Hz：

```
4.9426 ppm × 2.4e9 Hz = 11862 Hz ≈ 11.9 kHz
```

而本项目 `freq_sync.m` 的**无模糊估计范围**是：

```
freqEst_max = Rs / (2 × centerGap) = 250000 / (2 × 24) = 5208 Hz
```

（推导：前导 32 符号，分段长 Nseg = 8，首尾间隔 centerGap = 24 符号，
相位差无模糊范围 ±π ⇒ 最大可估 `Rs/(2×24)`。这正是 W6 日志里那句
"频偏接近估计上限 ±5208 Hz" 的来源。）

**对比结论**：

| 场景 | 等效频偏 | vs 估计器量程 ±5208 Hz |
|---|---|---|
| 本项目单板（W5 实测） | ~82 Hz | ✅ 远在量程内 |
| 示例那块板（异源） | ~11.9 kHz | ❌ **超出约 2.3 倍，估计必然失败** |
| 估计器 ppm 量程上限 | 5208/2.4e9 = **±2.17 ppm** | — |

**推论（写进报告的工程结论）**：
> 双板实验时，若两块板晶振差异 ≳ 2.2 ppm，前导相位差法将因相位模糊而失效。
> **必须先做硬件级 `FrequencyCorrection` 粗校正**（本示例流程），
> 把残余频偏压进 ±5 kHz，再交给数字估计器精调——
> 这就是"**粗校正（硬件，ppm 级）+ 细校正（软件，Hz 级）**"的分级架构。

这与 `notes/research_github.md` 里记录的参考项目
（`rx_freq_sync` 用"粗频偏 → 两级细频偏"分级收敛）**思路完全一致**，
说明分级是工程标准做法，我们的架构可以据此升级。

### 4.3 双板实验的操作前置（老师可提供第二块板）

若拿到第二块 Pluto，建议按此顺序：

1. **选定一块作参考源**，另一块作被测（示例做法）
2. **单音法测 ppm**：发 20/40/80 kHz 三音（或直接复用本项目单音脚本），
   接收端测峰频率，用 `p = (freceived − fref)/(fc + fref)×1e6` 算校正量
3. **写入 `FrequencyCorrection`**，把残余压到千赫兹级
4. **再跑本项目的 QPSK 帧收发**，让数字估计器接管
5. 用 `RadioID` 区分两块板（`'usb:1'` / `'usb:2'`）

### 4.4 一个尚未处理的真实误差项（理论深度点）

§2.2 已指出：真实频偏 = **载波偏置 + 采样率缩放** 两部分。
- 本项目 `freq_sync.m` 只估并补了**载波偏置**（相位旋转）
- **采样率缩放**会导致基带频率整体乘 `K`，表现为**符号定时缓慢漂移**
  （每符号的采样点数变了）

单板/短帧下 `K−1 ≈ 10^-8` 量级，可忽略；但
**长帧、长时间连续接收、或双板差异大时**，采样率失配会累积成定时漂移。
这个坑正好由 **Gardner 定时同步**（W7 候选）来兜底——
本示例给了它一个明确的"为什么需要"的物理解释。

---

## 5. 坑与注意事项

| # | 坑 | 说明 |
|---|---|---|
| 1 | **需要两块 Pluto** | 单板跑不了（本项目目前只有一块），但**公式与 ppm 概念单板也能用** |
| 2 | 模型需下载 | `plutoradioFrequencyCorrectionRx` 是 Simulink 模型，必须用 openExample 下载整个示例文件夹 |
| 3 | `RadioID` 必填 | 两块板同时连接时若不指定会歧义 |
| 4 | K 的推导有假设 | 假设**发射端晶振未漂移**、只有接收端漂移；实际两块都可能漂，故需**迭代**（示例也是先测再修正再验证） |
| 5 | 温度敏感 | 文档明确说漂移受**温度**影响 → 校正值不是永久常量，改环境温度后需重测 |
| 6 | `sdrrx` 是否有该属性 | 本示例用的是 **Simulink 模块**的 `FrequencyCorrection` 参数；`sdrrx('Pluto')` System object 是否暴露同名属性**需在 MATLAB 中实测确认**（`info(rx)` / 属性列表） |

---

## 6. 行动项

- [ ] 在 MATLAB 里确认 `sdrrx('Pluto')` 是否支持 `FrequencyCorrection` 属性（`info(rx)`）
- [ ] 报告 W5 结果改用 **ppm** 表述并标注估计器偏置（见 §4.1 的谨慎写法）
- [ ] **报告写入分级架构结论**：硬件 ppm 粗校正 + 软件 Hz 细校正（见 §4.2）
- [ ] 双板实验前，先按 §4.3 流程做硬件频偏校正
- [ ] 将"采样率缩放 → 定时漂移"作为 **W7 Gardner 定时同步**的动机写入设计文档
