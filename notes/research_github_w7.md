# GitHub 同类项目调研（W7 定时同步与相位跟踪）

> 日期: 2026-09-10 | 目的: 为 W7（定时精调 + 相位跟踪）寻找可参照的实现，
> 并核实"粗同步+精同步""DD-PLL vs Costas"等技术选择的社区主流做法。
> 检索方式: GitHub Search API（按 stars 排序）+ 逐仓库读取源码
> 关系: 本文是 `notes/research_github.md`（W2 调研）的续篇，聚焦 W7。

---

## 0. 结论速览

| # | 仓库 | 语言 | 对本项目的价值 | 优先级 |
|---|---|---|---|---|
| 1 | **jens-sam/qpsk-sdr-receiver-matlab** | MATLAB | ★★★★★ **W7a/W7b 有可直接参照的实现** | 最高 |
| 2 | **Trans-cending/Costas_Loop_for_QPSK** | MATLAB | ★★★★ **完整 Costas 环**（W7b 备选方案） | 高 |
| 3 | **Kavinesh799/QPSK-Receiver-...** | MATLAB | ★★★★ Early-Late TED + **显式建模 50 ppm 时钟偏差** | 高 |
| 4 | **rabieo/radio-qpsk-receiver** | Python | ★★★ **双板 Pluto 真实空口 bit-for-bit** | 中（双板用） |
| 5 | **Tiago-Ferreira-05/sdr-qpsk-receiver** | GNU Radio | ★★★ 课程项目标准配方：符号同步 + Costas + BER | 中 |

**三条最重要的结论**：

1. **W7a 有现成参考**：`jens-sam` 的 `symbol_rate_tracking.m` 实现的正是
   **判决导向 Early-Late TED + 线性插值 + 环路增益**——与我们的方案一致，
   **可直接参照，大幅降低实现风险**。
2. **W7b 有两个流派**：**Costas 环**（Trans-cending 完整实现、Tiago 的 GNU Radio）
   vs **判决导向 PLL**。这正好是 `spec_for_review.md` 的 Q2。
3. **"最大眼图开口"定时法被两个仓库采用**（jens-sam 粗定时、Kavinesh 的 EL），
   印证外部评审建议的"方案 A"是社区主流做法。

**一个反向发现**：多数同类项目是 **GNU Radio / Python**，**MATLAB 实现很少**。
本项目 100% MATLAB + 自研同步链，**在实现载体上有一定稀缺性**，可作为报告的差异化论述。

---

## 1. jens-sam/qpsk-sdr-receiver-matlab（最高参考价值）

- **链接**: https://github.com/jens-sam/qpsk-sdr-receiver-matlab
- **定位**: 课程作业（Part I–V 递进），QPSK SDR 接收机，MATLAB
- **文件结构**（全部为独立可运行脚本）:
  ```
  demod_timing_payload_recovery.m     % Part I: 下变频→匹配滤波→粗定时→前导→判决
  carrier_phase_tracking.m            % Part IV: 载波频偏估计 + 相位校正 + LMS 均衡
  symbol_rate_tracking.m              % Part V: ★ 符号率跟踪（= 我们的 W7a）
  preamble_symbol_equalizer.m         % 基于前导的均衡
  fractionally_spaced_equalizer.m     % 分数间隔均衡
  adaptive_equalizer_tracking.m       % 自适应均衡跟踪
  ```

### 1.1 ★ 符号率跟踪（`symbol_rate_tracking.m`）= 我们的 W7a 参照

核心循环（**判决导向 Early-Late TED + 线性插值**）：

```matlab
    n_late  = n_now + dtau;
    n_early = n_now - dtau;

    i_now   = floor(n_now);
    i_late  = floor(n_late);
    i_early = floor(n_early);

    a_now   = n_now   - i_now;
    a_late  = n_late  - i_late;
    a_early = n_early - i_early;

    if i_now < 1 || i_now+1 > Ly || ... % bounds check
       i_late < 1 || i_late+1 > Ly || ...
       i_early < 1 || i_early+1 > Ly
        break;
    end

    y_now = (1-a_now)*y(i_now) + a_now*y(i_now+1);
    y_late = (1-a_late)*y(i_late) + a_late*y(i_late+1);
    y_early = (1-a_early)*y(i_early) + a_early*y(i_early+1);

    sk = sign(real(y_now)) + 1j*sign(imag(y_now));

    z(kk) = y_now;

    tau(kk+1) = tau(kk) + mu * real(conj(sk - y_now) * (y_late - y_early));

    kk = kk + 1;
```

**要点**：
- `dtau` = Early/Late 的偏移量（半采样量级）
- 用**线性插值**取分数采样点（`y_now`/`y_late`/`y_early`），不依赖内插滤波器组
- `sk` = 对 `y_now` 的**判决**（QPSK 取符号）→ **判决导向**
- 误差 = `real(conj(sk - y_now) * (y_late - y_early))`，即"判决残差 × 早晚差"
- `tau` 用**一阶环路**更新（增益 `mu`）
- 输出 `tau_hist` **绘制定时相位收敛曲线**（我们报告要的图！）

> **对我们的价值**：这就是 W7a 的**最小可行实现**——线性插值而非复杂内插滤波器，
> 与我们的 `L=4` 过采样条件天然匹配（插值精度足够）。
> 且它演示了"**E/L 开环精调**"就够用，不需要完整 Gardner 环路 —— 印证评审建议的方案。

### 1.2 粗定时（`demod_timing_payload_recovery.m`）：逐相位功率最大化

```matlab
powers = zeros(L,1);
for k = 1:L
    samples = xBB_filt(k:L:end);
    powers(k) = sum(abs(samples).^2);
end
[~, best_k] = max(powers);
xBBd = xBB_filt(best_k:L:end);
```

**要点**：在 L 个采样相位中穷举，取**匹配滤波输出总功率最大**者 → 即"最大眼图开口"。

> 这就是外部评审建议的"**方案 A：最大匹配滤波输出**"，被实际课程作业采用。
> **对我们的价值**：可作为 W7a 的**基线对照**——若 TED+插值相比"逐相位功率最大化"
> 没有明显提升，就说明我们的定位精度已经很好，报告里可据此讨论。

### 1.3 频偏估计：重复前导 + 多段自相关

```matlab
% Known repeated preamble
preamble = repmat(cp,4,1);              % 前导重复 4 次
pilot_rx = xBBd(preamble_start : preamble_start + 4*Npilot - 1);

% Compute J using adjacent periods
J1 = sum(pilot_rx(Npilot+1:2*Npilot) .* conj(pilot_rx(1:Npilot)));
J2 = sum(pilot_rx(2*Npilot+1:3*Npilot) .* conj(pilot_rx(Npilot+1:2*Npilot)));
J3 = sum(pilot_rx(3*Npilot+1:4*Npilot) .* conj(pilot_rx(2*Npilot+1:3*Npilot)));

J = J1 + J2 + J3;

Dfc_est = angle(J) / (2*pi*Npilot*Tb_sym);
```

**要点**：前导设计成**重复 4 次**，然后对**相邻重复块**做共轭相关、**3 段平均**，
最后取相位 → 频偏。这是经典的**延时自相关（delay-and-multiply）**频偏估计。

> **与我们对比**：我们用"前导首尾分段"（间隔 24 符号）。
> 它用"相邻重复块"（间隔 = 1 个重复周期），**但有 3 段可平均**。
> **对我们的启示**：我们的前导是伪随机序列，若改成**重复结构**（如 4×8 符号），
> 即可获得 3 段平均 → 估计方差降为 1/3 → **等价于前导变长 3 倍的效果**，
> 且**不增加帧开销**！这可能比 `spec Q10` 里"加长前导"更划算。**值得验证。**

### 1.4 前导检测：滑动自相关 + 相对门限

```matlab
metric = abs(ryy);
beta = 0.6;
T = beta * max(metric);
aboveT = metric > T;
```
`beta = 0.6` 的**相对门限**与我们的归一化相关门限 **0.60** 数值一致（巧合但相互印证）。

---

## 2. Trans-cending/Costas_Loop_for_QPSK（W7b 备选方案）

- **链接**: https://github.com/Trans-cending/Costas_Loop_for_QPSK
- **作者**: yj Bian（东南大学）
- **文件**: `costas_sim.m`（单文件完整仿真）

**参数**：`Fs=16.384 MHz`，`fc=1.024 MHz`，`Rb=1.024 Mbps`，
相位偏 `-π/6`，**频偏 100 Hz**，环滤波系数 `c1=5, c2=3`

**QPSK Costas 误差检测器**（核心）：

```matlab
    Codebook_diff_recovery(1,i+1)=sign(lpfi(i));
    Codebook_diff_recovery(2,i+1)=sign(lpfq(i));
    e(i)=sign(lpfq(i))*lpfi(i)-sign(lpfi(i))*lpfq(i);
```

**环路结构**：`mul_i = costa_cos*trans_sig`，`mul_q = costa_sin*trans_sig`
→ 经过 LPF（`firpm` 设计）→ 误差 `e` → 环路滤波 → 更新 `phase(i)`
（用 `phase_diff(i) = -phase(i)*time + (2*pi*fc*time + phase_off)` 做相位修正）

**要点**：
- 误差 = **I、Q 的符号交叉乘积**（`sign(Q)·I − sign(I)·Q`）—— 这是 QPSK Costas 环的标准形式
- 用**符号非线性**消去调制（相当于硬判决），因此对 QPSK 的 4 重模糊天然免疫（锁定到最近象限）
- 环路系数有**切换**（`c1,c2 → c1_new,c2_new`），用于加快捕获

> **对我们的价值**：这是 `spec Q2` 的**直接答案选项**——
> 我们用"前导定初值 + DD-PLL"，而 Costas 环**不需要初值**（自捕获，但有 4 重模糊风险）。
> 两种路线的取舍可写进报告，并用**实测对比**。

---

## 3. Kavinesh799/QPSK-Receiver-Design-with-Carrier-and-Timing-Synchronization

- **链接**: https://github.com/Kavinesh799/QPSK-Receiver-Design-with-Carrier-and-Timing-Synchronization-MATLAB-Link-Level-Simulation-
- **内容**: `main.m` + `report.pdf`（链路级仿真，含载波与定时同步）

### 3.1 Early-Late TED（带滑动窗平均）

```matlab
function [symOut, mu_hist, e_hist] = el_simple(x, sps, tau_hat)
mu   = tau_hat-1;         % fractional clock phase
step = 0.1;               % phase correction step
thr  = 0.02;              % error threshold
win  = 10;                % averaging window (symbols)
...
    x_center = interp1(0:N-1, x, mu,        'linear', 0);
    x_early  = interp1(0:N-1, x, mu-sps/8,  'linear', 0);
    x_late   = interp1(0:N-1, x, mu+sps/8,  'linear', 0);

    % Early–Late error
    e = real(x_center)*(real(x_late)-real(x_early)) + ...
        imag(x_center)*(imag(x_late)-imag(x_early));
...
    if cnt == win
        e_avg = acc / win;
        if e_avg > thr
            mu = mu + sps - step;      % sampling late -> move earlier
        elseif e_avg < -thr
            mu = mu + sps + step;      % sampling early -> move later
        else
            mu = mu + sps;
        end
```

**与 jens-sam 的差异**：这里是**块处理**（每 10 符号平均一次误差，再步进 0.1 采样），
而非逐符号一阶环路。**两者都是"开环/半开环"精调**，不是完整 Gardner 闭环。

### 3.2 ★ 显式建模采样时钟偏差（50 ppm）

```matlab
Rs   = 500e3;
ppm  = 50e-6;                     % 50 ppm tolerance
Fs_nom = 2*Rs;                    % Nominal sampling rate
alpha_r = 1;                      % Random clock offset factor
Fs = Fs_nom * (1 + ppm*(2*alpha_r-1));   % Actual sampling rate
sps = Fs_nom / Rs;                % Samples per symbol
...
cfo_max = 1e9*ppm;
```

**要点**：**接收端采样率与标称值相差 ppm 级**，这正是参考 #2
（Pluto 频率校正）指出的"采样率失配"——**它会让符号定时缓慢漂移**。

> **对我们的价值**：给 W7 的"为什么需要定时跟踪"提供了**建模方法**：
> 我们可以在仿真里注入 `Fs*(1±ppm)` 的采样时钟偏差，
> 制造"定时缓慢漂移"场景，用来证明 W7a 的必要性（对应 `spec §8.3` 的 A3 实验）。

---

## 4. rabieo/radio-qpsk-receiver（双板参考）

- **链接**: https://github.com/rabieo/radio-qpsk-receiver
- **语言**: Python（NumPy，从零实现）
- **文件**: `capture.py` / `receiver.py` / `spectrum_viewer.py` / `check_pluto.py` / `capture.bin` / `capture.diag.png`

**结构**（README 原文要点）：
> - 📱 **One ADALM-Pluto transmits** — driven by an Android app
> - 💻 **A second Pluto receives**
> - 🧮 **This code decodes it** — recovering the original message **bit-for-bit, with zero errors**

**它归纳的四类空口损伤**（与我们的分析完全一致）：
> - **shifted in frequency**（收发时钟不一致）
> - **smeared in time**（不知道每个数据何时开始）
> - **spun around**（相位漂移）
> - **buried in noise**

**诊断图**（`capture.diag.png`）：**星座图 + 眼图 + 相关峰**三合一

> **对我们的价值**：
> 1. **证明双板 Pluto 空口 bit-for-bit 可行** → 支撑我们的双板计划
> 2. **诊断三联图**（星座 + **眼图** + 相关峰）是社区标准 →
>    我们的可视化清单（`spec §9.2`）**应补"眼图"**（我们目前没有眼图）

---

## 5. Tiago-Ferreira-05/sdr-qpsk-receiver（课程标准配方）

- **链接**: https://github.com/Tiago-Ferreira-05/sdr-qpsk-receiver
- **来源**: IST（葡萄牙高等理工学院）电信课程，组号 35
- **目标原文**: receive and decode a QPSK signal over a real RF link by ADALM-Pluto,
  **including symbol synchronization, Costas-loop carrier recovery and bit-error-rate measurement**

**flowgraph 清单**：

| 文件 | 作用 |
|---|---|
| `bpsk1.grc`, `bpsk2.grc` | BPSK 调制/解调热身（仿真） |
| `symbol_sync.grc` | **符号定时恢复链** |
| `section3.grc` | QPSK 接收机：符号同步 + **Costas 环**（仿真） |
| `pluto_sync.grc` | **真实 Pluto 空口实时接收** |
| `BER.grc` | **BER vs 信道噪声测量** |

**交付**: `report.pdf`（含星座、BER vs Eb/N0、RF 实测结果）

> **对我们的价值**：它印证了**课程级 QPSK 接收机的标准配方** =
> **符号同步 + Costas 环 + BER 测量 + 真实空口**。
> 我们已具备"符号同步（待做）+ BER + 真实空口"，**只差相位跟踪**——方向正确。
> 且它用 **Costas 环**而非 DD-PLL，再次说明 W7b 的路线选择值得在报告中讨论。

---

## 6. 本轮调研对项目的直接结论

### 6.1 对 W7a（定时精调）—— 风险大幅降低

| 发现 | 影响 |
|---|---|
| jens-sam 的 `symbol_rate_tracking.m` 就是 **DD Early-Late TED + 线性插值 + 一阶环路** | **有可运行参照，按最小实现即可** |
| 两个仓库都用**线性插值**（不是内插滤波器组） | 我们 `L=4` 过采样下线性插值足够，**实现可大幅简化** |
| "逐相位功率最大化"（最大眼图开口）被两个仓库采用 | 可作为**基线对照**，验证精调是否真的带来增益 |
| jens-sam 输出 `tau_hist` 定时收敛曲线 | **我们报告要的图，照此产出** |

### 6.2 对 W7b（相位跟踪）—— 路线选择有据

| 路线 | 代表实现 | 特点 |
|---|---|---|
| **判决导向 PLL**（spec 原方案） | jens-sam（定时用 DD）+ 我们的设计 | 需前导定初值以避跳周 |
| **Costas 环** | Trans-cending（MATLAB 完整）、Tiago（GNU Radio） | **不需初值、自捕获**；对 4 重模糊天然免疫（锁到最近象限） |

> **建议**：把 Costas 环作为**并行实现的备选**，用实测对比两者的
> ①收敛速度 ②低 SNR 表现 ③是否跳周，为 `spec Q2` 给出数据化答案。

### 6.3 ★ 一个可能比"加长前导"更划算的发现（重要）

jens-sam 把前导设计成**重复 4 次**，于是能对**相邻重复块**做 3 段相关并**平均**，
在不增加前导长度的前提下把频偏估计方差降低到 1/3。

对照 `spec Q10`：加长前导 32→64 可把估计误差降到 35%（代价：帧效率 83.8%→75.6%）。
**而"前导改为 4×8 重复结构 + 3 段平均"也能降方差约 3 倍，且不增加帧开销。**

> **建议列为 Q10 的第三个选项**，并做仿真验证后再决定。
> 注意：重复结构的**自相关旁瓣**比伪随机序列差（可能出现周期性旁瓣），
> 需检查对帧检测旁瓣/虚警的影响（我们已有 P_FA 测试可复用）。

> ### ⚠️ 后续更新（2026-09-10 当日）：**该推测已被实测证伪**
>
> 见 `notes/exp_w7_solution_study.md` §2（脚本 `experiments/exp_freq_estimator.m`）：
> 在**相同前导长度 p=32** 下实测频偏估计标准差：
>
> | 设计 | σ_f |
> |---|---|
> | 伪随机 + 首尾分段（现状） | 146.7 Hz |
> | **重复 4×8 + 相邻块多段平均** | **157.9 Hz（反而差 7.6%）** |
>
> **原因**：`σ_f ∝ σ_θ / T_sep`。重复结构的相邻块间隔（8 符号）
> 远小于现状的首尾间隔（24 符号），间隔缩小 3 倍的损失**超过**多段平均的收益。
>
> **教训**：跨项目的做法不能直接照搬，必须在本系统的参数下验证。
> 最终采纳的方案是 **DD-PLL（零带宽代价，12 dB 解帧率 35%→100%）**，
> 而非本节的"重复结构"。

### 6.4 对可视化清单的补充

社区标准的**诊断三联图 = 星座图 + 眼图 + 相关峰**。
我们目前有星座图与相关峰，**缺眼图** → 建议补入 `spec §9.2`。

---

## 7. 行动项

- [ ] W7a 参照 jens-sam 的 `symbol_rate_tracking.m` 实现 DD Early-Late TED + 线性插值
- [ ] 实现"逐相位功率最大化"作为**基线对照**，量化精调增益
- [ ] W7b 并行准备 Costas 环（参照 Trans-cending）与 DD-PLL，做对比实验（回答 Q2）
- [ ] 用 Kavinesh 的方法注入 `Fs*(1±ppm)` **采样时钟偏差**，验证定时漂移场景（A3 实验）
- [ ] ★ 仿真验证"**前导改重复结构 + 多段平均**"的频偏估计改善（新增到 Q10）
- [ ] 可视化补**眼图**（诊断三联图）
- [ ] 报告中增加"实现载体差异化"论述（同类项目多为 GNU Radio/Python，MATLAB 少）
- [ ] 双板实验前参考 rabieo 的四类损伤清单做检查表

---

## 附：本轮检索命令（可复现）

```bash
curl -s "https://api.github.com/search/repositories?q=plutosdr+qpsk&sort=stars&order=desc&per_page=10"
curl -s "https://api.github.com/search/repositories?q=pluto+sdr+receiver&sort=stars&order=desc&per_page=10"
curl -s "https://api.github.com/search/repositories?q=qpsk+receiver+matlab&sort=stars&order=desc&per_page=10"
curl -s "https://api.github.com/search/repositories?q=costas+loop+qpsk&sort=stars&order=desc&per_page=8"
# 读取单文件内容（base64 解码）
curl -s "https://api.github.com/repos/<owner>/<repo>/contents/<file>" | python -c "import json,sys,base64;print(base64.b64decode(json.load(sys.stdin)['content']).decode())"
```
