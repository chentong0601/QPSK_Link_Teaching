# W3 运行教程 — Pluto 单板空口 QPSK 帧收发

> 目标：让 Pluto 通过真实空口（两根天线）传递一条文字消息 "HELLO QPSK!"
> 脚本：`main_w3_overair.m`　|　必须在 **MATLAB GUI** 中运行

---

## 一、运行前检查（3 项，缺一不可）

### 1. 硬件连接
- [ ] Pluto 已用 Micro-USB 连电脑（插"电脑图标"那个口）
- [ ] **TX 口和 RX 口各装一根短天线**，两天线间隔 ≥10cm（别贴在一起）
- [ ] 确认设备已被识别：命令行 `ping 192.168.2.1` 有回复

### 2. 环境确认
- [ ] MATLAB 已安装 ADALM-Pluto Support Package
- [ ] 快速自检：命令行运行 `findPlutoRadio`，应返回 `RadioID: 'usb:0'`

### 3. RF 安全（务必遵守）
- [ ] TX 增益已设为 **-20 dB**（脚本默认，低功率安全）
- [ ] 天线已接好才运行（无天线发射有损坏风险）

---

## 二、运行步骤

### 步骤 1：设置当前文件夹
在 MATLAB 中，把**当前文件夹**切到工程根目录：
```
D:\ChenTong\SDR_project\QPSK_Link_Teaching
```
> 方法：MATLAB 上方地址栏粘贴该路径回车，或左侧文件树导航。

### 步骤 2：打开脚本
在左侧文件列表双击 `main_w3_overair.m`，或在命令行输入：
```matlab
edit main_w3_overair
```

### 步骤 3：运行
点击编辑器上方的绿色 **Run ▶** 按钮，或命令行输入：
```matlab
main_w3_overair
```

---

## 三、预期输出（逐行对照）

运行后命令窗口会依次打印：

```
[OK] 发送帧: 296 符号, 波形 1208 采样
[OK] 正在 2.400 GHz 发射, TxGain=-20 dB
## Establishing connection to hardware. This process can take several seconds.
（固件版本警告 v0.31 —— 正常，可忽略）
[OK] 抓取 5 帧, 共 40960 采样

===== 空口结果 =====
帧起点: xxxx, 频偏估计: xxx.x Hz
帧头: type=0 nBytes=11 frameNum=0 crcOK=1
解出: "HELLO QPSK!"
[PASS] 真实空口成功!
[OK] 已停止发射
[OK] 图已保存: plots/w3_overair_constellation.png
```

**成功标志**：看到 `[PASS] 真实空口成功!` 且 `解出: "HELLO QPSK!"`

同时弹出一张星座图，4 个点应收敛（空口有噪声，比仿真略散，但能看出 4 团）。

---

## 四、结果解读

| 输出项 | 含义 | 正常范围 |
|---|---|---|
| 帧起点 | 接收端找到的帧位置 | 任意正整数（数据流中的位置）|
| 频偏估计 | 收发晶振频差 | 单板同源 → 通常 <50 Hz |
| crcOK=1 | 帧头校验通过 | 应为 1 |
| 解出消息 | 还原的文字 | 应为 "HELLO QPSK!" |

---

## 五、故障排查

| 现象 | 原因 | 解决 |
|---|---|---|
| 报错 `sdrtx 需要 Support Package` | 在 -batch 或无GUI环境运行 | 必须在 MATLAB GUI 里跑 |
| 报错 `未检测到帧` | 天线没接好/距离太远/增益太低 | 检查天线；缩短距离(<30cm)；增大 RxGain |
| 解出乱码 / [FAIL] | 信噪比不够 | 天线靠近；RxGain 调到 40；降低距离 |
| 报错 `帧段过短` | 抓取采样数不足 | 增大 `params.RxFrames`（如 16384）|
| 报错 `Payload 过长` | 消息超 62 字节 | 缩短消息 |
| 设备无响应 | USB 供电不足 | 插第二个电源口 |

---

## 六、运行成功后的下一步

1. **换消息测试**：修改脚本里 `msg = 'HELLO QPSK!';` 为其他文字（≤62字节），重跑
2. **拉远距离**：把两根天线逐渐拉开，观察解调是否还成功 → 这是"信道影响"实验
3. **记录数据**：把每次的频偏估计、是否 [PASS] 记录下来，作为报告实测数据

---

## 七、原理速览（为什么这样做）

```
发射: "HELLO QPSK!" → 组帧(前导+帧头+payload) → QPSK → 成形 → Pluto发射
                          ↓ 2.4GHz 电磁波（两根天线间）
接收: Pluto抓取 → 滑动相关找帧起点 → 频偏估计补偿 → 解调 → 解扰 → "HELLO QPSK!"
```
与 W2 仿真的唯一区别：波形走的是**真实电磁波**（含真实噪声、频偏、多径），而不是软件加的 AWGN。
