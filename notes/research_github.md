# GitHub 同类项目调研（W2 设计参考）

> 日期: 2026-09-09 | 目的: W2 同步算法设计前，调研 GitHub 成熟实现，避免重复造轮子，并为报告找文献级参考。

## 调研结论速览

**直接相关的成熟项目稀少（stars 普遍低），但有一个高价值课程设计项目与我们的定位高度吻合**：
`ljd1996/pluto_design` —— "基于 PlutoSDR 的网络协议课程设计"（MATLAB），实现了完整的
"同步头 + 组帧 + 加扰 + CRC + 频偏同步 + 定时恢复 + 相位同步 + 解调"链路，正是我们 design.md 规划的内容。

---

## 1. 重点参考项目：ljd1996/pluto_design

- **定位**：课程设计（与我们的课程项目场景相同）
- **语言**：MATLAB + PlutoSDR
- **内容**：BPSK 链路为主，另含 LTE 接收机 + 802.11a 目录
- **顶层入口**：`transmmit.m`（发射）/ `recieve.m`（接收）

### 1.1 接收链路同步链（bpsk_rx_func.m 主流程）—— 我们 W2 的最佳参考

```
rx_signal
  → rcosdesign 匹配滤波 (upfirdn)
  → 幅度归一化
  → rx_timing_recovery()   : Gardner 定时恢复 (完整环路: 内插+误差提取+环路滤波)
  → rx_package_search()    : 滑动相关帧搜索 (找同步头)
  → 三级 rx_freq_sync()    : 粗频偏 → 两级细频偏 (分级收敛, 增大估计范围+精度)
  → rx_phase_sync()        : 初始相位估计
  → rx_phase_track()       : 残余相位跟踪
  → rx_delete_pilot()      : 去导频
  → rx_bpsk_demod()        : 解调 (含 EVM 输出!)
  → descramble()           : 解扰
  → crc32()                : 校验 (尾部 32bit CRC)
```

### 1.2 关键算法实现要点（可借鉴到我们 QPSK 链路）

| 模块 | 他们的做法 | 我们的借鉴点 |
|---|---|---|
| 同步头生成 | `tx_gen_m_seq([1 0 0 0 0 0 1])` m序列 + 调制 | 我们已是伪随机 QPSK 前导，思想一致 ✓ |
| 帧搜索 | `rx_package_search`: 符号级滑动相关 `abs(signal(i-N+1:i) * local_sync')` 取峰 | 与我们 design.md §4.2 一致；注意他们在**定时恢复之后**才做帧搜索 |
| 频偏估计 | `rx_freq_sync`: 信号**平方**后自相关取相位（M 次方去调制法，BPSK用2次方） | 我们是 QPSK → 需 **4 次方**去调制（区别于他们的 2 次方），或改前导分段相关法（更简单，见我们 design.md §4.3） |
| 定时恢复 | `rx_timing_recovery`: **Gardner 算法**完整实现（内插滤波器 + Gardner 误差 + 环路滤波） | 复杂度高；我们单板频偏≈0 可先做"帧检测后固定抽样"，Gardner 作为拓展项 |
| 校验 | CRC32（尾部 32bit） | 我们帧头用了极简 8bit 校验；可升级为 CRC 到 payload |

### 1.3 频偏估计算法细节（rx_freq_sync.m 分析）

```matlab
zr = sync_samples.^2;              % BPSK: 2次方去调制
r0(m) = mean(zr(1+m:end).*conj(zr(1:end-m)));  % 延时自相关
deltaf = angle(sum(r0)) / (pi*(N+1)*Tchip) / 2; % 换算频偏
out = samples_package .* exp(-1i*2*pi*deltaf*(1:len)*Tchip); % 补偿
```
- 本质 = **M 次方去调制 + 延时自相关**（与我们的"前导分段相位差法"同族，只是去调制手段不同）
- 分级（粗+细）是因为单级受 ±1/(2T_sep) 范围限制 → **印证了我们 design.md §4.3 的推导结论**

---

## 2. 其他相关项目（参考度递减）

| 项目 | 说明 | 对我们的价值 |
|---|---|---|
| sofyan-syahputra/ofdm-plutosdr-matlab | OFDM 无线文件传输（MATLAB） | 文件/图像分帧传输思路可参考，但 OFDM 复杂度高，不采用 |
| rabieo/radio-qpsk-receiver | 双 Pluto QPSK 真实空口（Python/GNU Radio） | 证明 QPSK 双板空口可行；我们 W4 双板实验可对照 |
| Tiago-Ferreira-05/sdr-qpsk-receiver | QPSK 接收机（GNU Radio + Pluto） | 符号定时等思路，Python 生态非本项目主线 |
| 11tools/AD936X_QPSK_VTX | QPSK 视频 TX（GNU Radio） | 佐证"视频超容量"结论；我们选图像渐进是合理的 |

---

## 3. 对我们的启示（W2 及后续设计决策）

1. **同步链顺序**（重要借鉴）：参考项目是 **先定时恢复 → 再帧搜索**。我们单板频偏≈0、无多径时，可简化为 **帧搜索(找起点) → 固定抽样**；但要在报告中**对比说明**两种顺序的取舍（有频偏/定时漂移时需先定时，教学上可留作拓展）。

2. **QPSK 频偏估计注意**：参考项目的 BPSK 用 2 次方去调制；**QPSK 需 4 次方**（有 4 重相位模糊）。两种路线：
   - 路线1（简单，教学优先）：前导**分段相关相位差**（design.md §4.3），不受 QPSK 模糊影响，实现直观
   - 路线2（更工程）：4 次方去调制 + 自相关，但估计范围缩 4 倍
   - **决策：W2 先做路线1**，报告里讨论路线2 为何 QPSK 不直接套 BPSK 的平方法 → 理论深度点

3. **报告可引用的"对标"**：报告"相关工作"章节可直接引用 ljd1996（同为课程设计、BPSK）并说明我们的**差异与增量**（QPSK / 多内容源 / 同步顺序取舍 / 单板验证方法论）——这是加分的"文献综述"写法。

## 4. 行动项

- [ ] W2 实现：帧搜索（滑动相关）+ 频偏估计（分段相关相位差法）+ 固定抽样
- [ ] 报告"相关工作"引用 ljd1996/pluto_design，写差异化对比
- [ ] 可选拓展：Gardner 定时恢复（借鉴其 rx_timing_recovery 实现，改 QPSK）
