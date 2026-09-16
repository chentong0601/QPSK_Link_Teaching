# 参考笔记：MathWorks 频谱分析示例（ADALM-Pluto，MATLAB + Simulink）

> 来源 1（MATLAB 版）: https://ww2.mathworks.cn/help/comm/plutoradio/ug/spectral-analysis-with-adalm-pluto-radio.html
> 来源 2（Simulink 版）: https://ww2.mathworks.cn/help/comm/plutoradio/ug/spectral-analysis-with-adalm-pluto-radio-simulink.html
> 整理日期: 2026-09-10 | 类型: 官方文档摘录 + 项目适配分析
> 说明: 两页是**同一示例的两种实现**——MATLAB 版用 System object，Simulink 版用模型 `spectralAnalysis`。
>       本笔记合并整理：§1–§4 为 MATLAB 版，§5 为 Simulink 版。

---

## 1. 示例定位

用 **System object + `spectrumAnalyzer`** 对接收信号做**实时频谱分析**。

- 默认用**录制文件**运行，**无需硬件**
- 可选空口实时接收：RTL-SDR / **ADALM-Pluto** / USRP（三选一）
- 可调中心频率对准目标频段，然后用频谱分析仪观察并测量（峰值、占用带宽等）
- Simulink 版本见 [Spectrum Analysis of Signals in Simulink](https://ww2.mathworks.cn/help/comm/ug/spectral-analysis-of-signals-in-simulink.html)

**用到的工具箱/支持包**：

| 组件 | 本项目是否已有 |
|---|---|
| Communications Toolbox | ✅ |
| DSP System Toolbox | ✅ |
| Communications Toolbox Support Package for ADALM-PLUTO Radio | ✅ |
| RTL-SDR / USRP / NI USRP 支持包 | 不需要（示例的多无线电兼容设计） |

---

## 2. 完整代码（三段）

### 2.1 初始化：获取用户输入并创建信号源

```matlab
cmdlineInput = false;
if cmdlineInput
%     Request user input from the command-line for application parameters
    userInput = helperSpectralAnalysisUserInput;
%     Set initial parameters
    [SAParams, sigSrc] = helperSpectralAnalysisConfig(userInput);
else
%     Set initial parameters
    load defaultInputSpecAnalysis.mat
    [SAParams, sigSrc] = helperSpectralAnalysisConfig;
end
```

**要点**：`cmdlineInput = false` 时走默认参数路径（从 `.mat` 载入），
输出两个关键对象：
- `SAParams` —— 参数结构体（`FrontEndSampleRate`、`CenterFrequency`、`FrontEndFrameTime`、`isSourceRadio`、`isSourcePlutoSDR` 等）
- `sigSrc` —— **信号源对象**，用 `sigSrc()` 直接调用即可取一块采样（Pluto 场景下本质就是 `sdrrx('Pluto')`）

### 2.2 创建频谱分析仪对象

```matlab
hSpectrum = spectrumAnalyzer(...
    'Name',             'Passband Spectrum',...
    'Title',            'Passband Spectrum', ...
    'Method',           'Welch', ...
    'SpectrumType',     'Power density', ...
    'FrequencySpan',    'Full', ...
    'SampleRate',       SAParams.FrontEndSampleRate, ...
    'FrequencyOffset',  SAParams.CenterFrequency, ...
    'YLimits',          [-120 10], ...
    'YLabel',           'Magnitude-squared, dB', ...
    'Position',         figposition([50 30 30 40]));
```

**关键属性含义**：

| 属性 | 值 | 说明 |
|---|---|---|
| `Method` | `'Welch'` | Welch 平均周期图法，平滑谱线、降低方差 |
| `SpectrumType` | `'Power density'` | 功率谱密度（dB/Hz） |
| `FrequencySpan` | `'Full'` | 显示整个采样带宽 |
| `SampleRate` | 前端采样率 | 决定横轴范围 |
| `FrequencyOffset` | 中心频率 | 把横轴**搬到射频绝对频率**（如 2.4 GHz），而不是基带 -fs/2~fs/2 |
| `YLimits` | `[-120 10]` | 纵轴 dB 范围 |

### 2.3 流处理主循环

```matlab
% Initialize radio time
radioTime = 0;

% Main loop
while radioTime < userInput.Duration
  % Receive baseband samples (Signal Source)
  if SAParams.isSourceRadio
      if SAParams.isSourcePlutoSDR
          rcv = sigSrc();
          lost = 0;
          late = 1;
      elseif SAParams.isSourceUsrpRadio
          rcv= sigSrc();
          lost = 0;
      else
          [rcv,~,lost,late] = sigSrc();
      end
  else
    rcv = sigSrc();
    lost = 0;
    late = 1;
  end

    rcv = rcv - mean(rcv);  % Remove DC component.
    step(hSpectrum, rcv);

  % Update radio time. If there were lost samples, add those too.
  radioTime = radioTime + SAParams.FrontEndFrameTime + ...
    double(lost)/SAParams.FrontEndSampleRate;
end

% Release all System objects
release(sigSrc);
release(hSpectrum);
```

**三个设计要点**：

1. **三种数据源统一接口**：Pluto/USRP 的返回是单输出 `rcv`，RTL-SDR 的返回是
   `[rcv,~,lost,late]`（含丢样/迟到信息）。用 `if/elseif` 分支适配。
2. **去直流**：`rcv = rcv - mean(rcv);` —— 零中频接收机（含 Pluto）存在 DC 偏置，
   不去掉会在频谱中心出现尖峰。**这一行对本项目有直接价值，见 §4.1**。
3. **无线电时间推进**：`radioTime` 累加"帧时长 + 丢样补偿"，而不是简单计数，
   保证在丢样时仍按真实时间运行。

---

## 3. 两个必须注意的坑

### 坑 1：代码**不能**直接复制运行

示例依赖三个外部文件，都在示例文件夹内：

| 文件 | 作用 |
|---|---|
| `helperSpectralAnalysisConfig.m` | 根据输入创建参数结构体 + 信号源对象 |
| `helperSpectralAnalysisUserInput.m` | 命令行交互式参数输入 |
| `defaultInputSpecAnalysis.mat` | 默认参数集 |

**必须**通过页面上的 **"Copy openExample Command"** 按钮下载整个示例文件夹（含 helper），
否则直接粘贴会报"函数或变量未定义"。

### 坑 2：文档正文有翻译/串文错误

页面正文写：

> "然后，它在循环中调用信号源和 **FM 广播接收机**。"

这是**从 FM 广播接收示例串过来的错误文字**。本示例中根本没有 FM 接收机，
循环里只调用 `sigSrc`（信号源）和 `hSpectrum`（频谱分析仪）。不要被这句误导。

---

## 4. 对本项目的价值与适配

### 4.1 可立即借鉴：接收链补 DC 去除

Pluto 是零中频（Zero-IF）架构，DC 偏置不可避免。本项目 **W3 空口实测数据**
（`results/w3_rxData.mat`）可用来验证 DC 偏置是否显著、去掉后噪声底是否下降。

**适配位置**：`receiver/rx_frame.m` 第 2 步（帧检测）之前，或 `main_w3_overair.m`
抓取数据后立即处理：

```matlab
rxData = rxData - mean(rxData);   % 去直流 (参考官方示例做法)
```

> 注意：本项目用**归一化相关**做帧检测（ρ 与幅度无关），DC 偏置主要影响
> 噪声底与判决门限，不影响归一化相关本身。因此收益需实测确认，不能想当然。

### 4.2 可用于答辩演示：实时频谱 + 星座图

`spectrumAnalyzer` 是 System object，可直接 `step(hSpectrum, rcv)` 推入数据流，
无需自己算 FFT。对本项目参数适配如下：

```matlab
hSpectrum = spectrumAnalyzer(...
    'Method','Welch', 'SpectrumType','Power density', ...
    'FrequencySpan','Full', ...
    'SampleRate',      params.SampleRate,        % 1e6
    'FrequencyOffset', params.CenterFrequency,   % 2.4e9
    'YLimits',[-120 10]);
```

搭配现有 `plots/w3_overair_constellation.png`（星座图），可组成
**"频谱 + 星座"双视图**的现场演示界面，比只放静态图更有说服力。

### 4.3 结构对照：官方示例 vs 本项目

| 维度 | 官方示例 | 本项目 |
|---|---|---|
| 数据源 | `sigSrc()` 统一封装（文件/三种 SDR） | `rx_receiver` 的 `rxSource`（函数句柄或向量） |
| 循环目标 | 跑满 `Duration` 秒 | 解满 `nFrames` 帧 |
| 循环体 | 去 DC → 推频谱仪 | 帧检测 → 解调 → 消费缓冲 |
| 输出 | 频谱图 | payload + 统计 |

**结论**：两者的"持续循环 + 每轮读一块"骨架是**同构**的，
本项目的 `rx_receiver.m` 已经把循环体换成了完整的接收机处理链。
官方示例证明了这个骨架是 MathWorks 推荐的标准写法。

---

## 5. Simulink 版本（模型 `spectralAnalysis`）

> 来源: https://ww2.mathworks.cn/help/comm/plutoradio/ug/spectral-analysis-with-adalm-pluto-radio-simulink.html
> 本页无独立代码块，是**模型说明页**；官方明示"MATLAB 版是本页的 MATLAB 实现"——
> 两页功能等价，差别只在实现载体（System object vs Simulink 模型）。

### 5.1 模型做了什么

`spectralAnalysis` 模型在**复基带**做**基于 FFT 的频谱分析**，提供两个视图：

| 视图 | 工程含义 |
|---|---|
| **无杂散动态范围（SFDR）** | 接收机能同时看到的最强信号与最弱杂散之差 → 衡量接收链线性度 |
| **接收信号定性 SNR** | 直观判断信号质量、噪声底位置 |

### 5.2 默认数据与运行

- 默认用**文件录制数据**运行，数据文件名为 **`spectrum_capture.bb`**（`.bb` = baseband）
- 示例截图展示的是 **FM 广播频段：88 MHz ~ 108 MHz** 的频谱
- 可换用 RTL-SDR / **ADALM-Pluto** / USRP 空口实时接收（与 MATLAB 版相同的支持包要求）
- **`FrequencyOffset` 概念同样存在**：调中心频率即可把无线电"调谐"到目标频段

### 5.3 支持的测量项（本页明确列出）

| 测量项 | 英文 | 对本项目的用途 |
|---|---|---|
| 峰值 | peaks | 找载波/杂散位置 |
| 占用带宽 | occupied bandwidth | **验证 RRC 成形后的实际带宽**（本项目滚降 0.35） |
| 邻道功率比 | adjacent channel power ratio (ACPR) | **验证发射频谱不"溅射"到邻道** ← 价值最高 |
| 谐波 / 互调电平 | harmonic & intermodulation levels | 检查发射链非线性（增益过高时出现） |
| 无杂散动态范围 | spur-free dynamic range | 辅助确定 RxGain（对应 W5 增益扫描） |

### 5.4 与本项目的关系

**① ACPR / 占用带宽 → 可以量化验证我们的 RRC 成形质量。**
本项目 `tx_baseband.m` 用 RRC（`RollOff = 0.35`，`RRCSpan = 6`）做脉冲成形，
理论占用带宽 ≈ `Rs × (1+α)` = 250 k × 1.35 ≈ **337.5 kHz**。
用频谱仪的"占用带宽"读数可以直接对照这个理论值——这是报告里**可写进实验结论**的定量验证。

**② SFDR / SNR 视图 → 解释 W5 增益扫描的非单调现象。**
W5 实测发现 RxGain=35 dB 时成功率反而掉到 40%（其余 100%）。
当时归因于"真实空口噪声波动"。频谱仪能直接看出：增益过高时噪声底是否抬升、
是否出现杂散——这能把当时的**定性猜测变成定量结论**。

**③ Simulink 模型可作为答辩"系统级视角"。**
本项目主线是 `.m` 脚本 + 函数（便于讲解算法细节），
Simulink 模型则适合展示**数据流与模块边界**。若时间允许，可用 `spectralAnalysis`
模型做一页"系统框图 + 实时频谱"的演示，与 `.m` 链路的算法讲解互补。

### 5.5 打开方式

在 MATLAB 命令窗口用页面上的 **"Copy openExample Command"** 得到的命令打开示例，
或用 `openExample` 检索 "Spectral Analysis"。
**注意**：与 MATLAB 版同样**不能只复制正文**——需要下载整个示例文件夹
（Simulink 模型 `.slx` + 回调脚本 + 数据文件 `spectrum_capture.bb`）。

---

## 6. 行动项

- [ ] 用 `results/w3_rxData.mat` 实测 DC 偏置量级，评估是否值得入链
- [ ] **用频谱仪测发射波形的占用带宽，对照理论值 337.5 kHz 验证 RRC 成形**
- [ ] **用频谱仪重看 W5 增益扫描数据，解释 RxGain=35 dB 成功率跌落的原因**
- [ ] （可选）把 `spectrumAnalyzer` 集成进 `main_w6_receiver`，做实时双视图演示
- [ ] （可选）写不依赖 helper 的独立频谱脚本，直接接 Pluto 跑
- [ ] 报告"相关工作/工具"一节可引用本示例，说明项目实现与官方标准写法的异同
