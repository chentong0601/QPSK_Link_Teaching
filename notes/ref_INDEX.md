# 参考资料索引（Reference Index）

> 本文件是项目**参考资料的统一入口**。
> 目的：把开发过程中查阅的外部文档/示例沉淀到工程内，**避免重复检索**，
> 也让后续开发（含 AI 协作会话）**从项目里就能直接看到**所需参考。

---

## 使用说明

**新增参考资料时**：
1. 在 `notes/` 下新建 `ref_<主题>.md`
2. 在本索引表格中登记（主题 / 文件 / 用途 / 关键结论）
3. 若资料对开发有直接行动指令，写入对应条目的"行动项"

**撰写规范**（保证可复用）：
- 记录**原始链接**与整理日期
- 代码块**原样保留**，不要意译
- 必须包含 **"对本项目的价值与适配"** 一节，把外部资料落到本项目
- 记录**文档本身的坑**（如依赖缺失、原文错误），避免下次重复踩

**抓取技巧**：
- MathWorks **中文站 `ww2.mathworks.cn` 可能返回安全验证页**（抓不到正文），
  此时把 URL 换成**英文站 `www.mathworks.com`** 同路径即可拿到完整内容（已验证有效）
- 官方示例通常**不能只复制正文代码**（依赖 helper 文件 / `.slx` / `.mat`），
  需用页面上 "Copy openExample Command" 按钮下载整个示例文件夹

---

## 参考资料清单

| # | 主题 | 文件 | 来源 | 对本项目的用途 |
|---|---|---|---|---|
| 1 | MathWorks 频谱分析示例（Pluto，MATLAB + Simulink） | `notes/ref_matlab_spectral_analysis.md` | [MATLAB 版](https://ww2.mathworks.cn/help/comm/plutoradio/ug/spectral-analysis-with-adalm-pluto-radio.html) · [Simulink 版](https://ww2.mathworks.cn/help/comm/plutoradio/ug/spectral-analysis-with-adalm-pluto-radio-simulink.html) | 频谱分析仪用法；DC 去除；占用带宽/ACPR 验证 RRC 成形；SFDR 解释增益扫描 |
| 2 | Pluto 频率校正（Frequency Correction, ppm） | `notes/ref_pluto_frequency_correction.md` | [Simulink 版](https://ww2.mathworks.cn/help/comm/plutoradio/ug/frequency-correction-for-adalm-pluto-radio-in-simulink.html) | ppm 频偏量化；**双板实验前置校正**；硬件粗校正+软件细校正分级架构；解释定时漂移来源 |
| 3 | Pluto 频偏标定（Frequency Offset Calibration, Hz） | `notes/ref_pluto_freq_offset_calibration.md` | [Simulink 版](https://www.mathworks.com/help/comm/plutoradio/ug/frequency-offset-calibration-with-adalm-pluto-radio-simulink.html) | **单音+FFT找峰**测频偏（可交叉验证本项目相位差法）；双板 Hz 域粗调流程；SFDR≈34 dB 参照值 |

---

## 关键结论速查（TL;DR）

### 来自 #1 MathWorks 频谱分析示例

**可直接用的技术点**
- `rcv = rcv - mean(rcv);` — 零中频（Pluto）DC 偏置去除，接在接收数据入口
- `spectrumAnalyzer('Method','Welch','FrequencyOffset',centerFreq,...)` — 免自写 FFT 的实时频谱
- `FrequencyOffset` 属性把横轴从基带搬到射频绝对频率

**两条待验证的行动项**
- 发射波形占用带宽应 ≈ `Rs×(1+α)` = 250k×1.35 = **337.5 kHz**（可验证 RRC 成形）
- 用频谱重看 W5 增益扫描数据 → 解释 RxGain=35 dB 成功率跌落到 40% 的原因

**文档坑（不要重复踩）**
- 示例代码**不能只复制正文**：依赖 helper 文件/`.slx`/`.bb` 数据，必须用 openExample 下载整个示例文件夹
- MATLAB 版页面正文有串文错误（误写"FM 广播接收机"，实为频谱分析仪）

### 来自 #2 Pluto 频率校正示例

**核心公式**（ppm 校正量）
```
p = (freceived - fref) / (fc + fref) * 1e6        [ppm]
K = (fc + fref) / (fc + freceived)                [漂移因子]
```

**★ 最重要的一条结论（双板实验的拦路虎）**
- 本项目 `freq_sync.m` 的无模糊估计上限 = `Rs/(2×centerGap)` = 250k/(2×24) = **±5208 Hz ≈ ±2.17 ppm**
- 而官方示例那块接收板的误差是 **-4.9426 ppm ≈ 11.9 kHz** → **超出量程 2.3 倍，数字估计必然失败**
- 推论：**双板实验必须先做硬件 `FrequencyCorrection` 粗校正**，再交给软件精调
  → 确立"**硬件 ppm 粗校正 + 软件 Hz 细校正**"的分级架构

**其他要点**
- 真实频偏 = **载波偏置 + 采样率缩放**两部分；本项目目前只补了载波偏置
- 采样率缩放（K−1）会让符号定时缓慢漂移 → 正好是 **W7 Gardner 定时同步**的动机
- W5 的 -82.2 Hz 换成 ppm = **0.034 ppm**（但混有估计器偏置，勿全归因硬件）
- `RadioID='usb:1'` 用于**两块板同时连接时指定具体板子**（双板实验必备）
- `ShowAdvancedProperties=true` 暴露高级属性；`info(tx)` 读回硬件实际值

**文档坑**
- 需两块 Pluto 才能跑（本项目目前一块）
- K 的推导假设只有接收端漂移 → 实际需迭代校正
- 漂移受**温度**影响 → 校正值不是永久常量
- `sdrrx('Pluto')` 是否暴露同名属性**待实测确认**（示例用的是 Simulink 模块参数）

### 来自 #3 Pluto 频偏标定示例

**★ 与 #2 的分工（官方原文明确）**
- #3（本页）：**只修中心频率**，用**单音 + FFT 找峰**，结果单位 **Hz**，**人工闭环**
- #2：**中心频率 + 基带采样率**，用三音反推 ppm，结果单位 **ppm**，写参数
- 一句话：**#3 负责"量出来"，#2 负责"算成 ppm 写进硬件"**

**核心公式**（峰值频率换算）
```
Foffset = IndexofMaxAmplitude * FrameSize / (FFTLength * FrameSampleTime)
        ≈ 峰值谱线号 × (SampleRate / FFTLength)      [= 谱线号 × 频率分辨率]
频偏 = 峰值频率 − 12000 Hz                            [发射标称 12 kHz]
```

**★ 有两条对本项目直接可用**
- **第二种独立测频偏方法**（单音 FFT 找峰）→ 可与本项目 `freq_sync` 相位差法**交叉验证**
- **双板最简流程**：测出 Δf(Hz) → 直接改 RX 中心频率 → 压进量程（比 ppm 路线更容易落地）

**△ 又一个量程告警**
- 本示例实测频偏 ≈ **−5 kHz**，而本项目估计器上限 **±5208 Hz** → **几乎正好在边界上**
  （此结论不依赖示例的中心频率，比较的是绝对 Hz）
  → 再次印证：“双板不做硬件粗校正就是赌博”

**参考数值**：Pluto 接收机 **SFDR ≈ 34 dB**

**文档坑**
- 同样需两块 Pluto；两个模型 `plutoradiofreqcalib` / `plutoradiofreqcalib_rx` 都要
- 公式左边写成 `Foffset` 但算的是**峰值频率**，真正频偏要**再减 12000 Hz**（名称误导）
- 补偿需手动改参数再手动验证，不适合自动化
- **中文站 `ww2.mathworks.cn` 本次返回安全验证页 → 改用英文站 `www.mathworks.com` 成功**

---

## 与本项目其他文档的分工

| 文件 | 性质 | 说明 |
|---|---|---|
| `notes/design.md` | **自研** | 本项目的设计文档 |
| `notes/report_draft.md` | **自研** | 项目报告（含实测数据） |
| `notes/stage_w6_receiver.md` | **自研** | W6 实验笔记 |
| `notes/w3_run_tutorial.md` | **自研** | 运行教程 |
| `notes/research_github.md` | **他研** | GitHub 同类项目调研 |
| `notes/ref_*.md` | **外部资料** | 官方文档/示例摘录，由本索引管理 |

---

## 待补充主题（规划）

**外部资料待补**
- [ ] Pluto 硬件参考：AD9363 增益/带宽/采样率约束
- [ ] `sdrrx/sdrtx` 官方使用文档要点
- [ ] 符号定时同步（Gardner）算法参考（W7 候选）
- [ ] 相位跟踪 PLL 算法参考（W7 候选）

**由参考资料转化出的小工具待做**
- [ ] 单音 + FFT 找峰测频偏脚本 → 与 `freq_sync` 相位差法**交叉验证**（来自 #3）
- [ ] 发射波形占用带宽测量（验证 RRC = 337.5 kHz）（来自 #1）
- [ ] 用频谱重看 W5 增益扫描数据（解释 35 dB 跌落）（来自 #1）
- [ ] 在 MATLAB 确认 `sdrrx('Pluto')` 是否支持 `FrequencyCorrection`（来自 #2）
