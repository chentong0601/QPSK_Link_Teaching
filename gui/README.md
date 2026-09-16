# gui/ — SDR Showcase GUI

> 实验3 「构建通信收发机」课程展示 GUI
> 4-tab 框架：实验导航 / 实时监视 / 流程可视化 / 数据体检

## 启动

```matlab
cd D:\ChenTong\SDR_project\QPSK_Link_Teaching
addpath('gui')
sdr_showcase
```

**需要**：MATLAB R2020b+（`uigridlayout`）/ R2016b+（`uifigure` + `uitabgroup`）

## 文件清单

| 文件 | 状态 | 功能 |
|---|---|---|
| `sdr_showcase.m` | ✅ | 主入口；建 uifigure + uitabgroup + 4 tabs |
| `tab_sanity.m` | ✅ **G1 完成** | Tab 4 数据体检（完整可用） |
| `tab_stages.m` | ⏸ G2 占位 | Tab 1 实验导航（设计说明） |
| `tab_live.m` | ⏸ G3 占位 | Tab 2 实时监视（设计说明） |
| `tab_flow.m` | ⏸ G4 占位 | Tab 3 流程可视化（设计说明） |

## G1 数据体检 Tab 使用步骤

1. 启动 `sdr_showcase`
2. 切到 **Tab 4 数据体检 Sanity**
3. 顶部 [选择文件...] 或下拉列表选 `results/*.mat`
4. 自动调用 `experiments/rx_sanity_check.m`：
   - 左列填出诊断数字（样本数/量化级/精确零/峰值/边缘堆积比）
   - 右列 4 子图画出（I直方图/IQ散点/幅度直方图/功率包络）
   - 判定文字上色：🟢 数据健康 / 🟠 采集可疑 / 🔴 ADC 饱和
5. [导出诊断 .md] 一键生成体检报告

## 复用原则（重要）

GUI 只**调用**现有 .m 函数，不重写算法：
- ✅ Tab 4 调用 `experiments/rx_sanity_check.m`（已升级为 GUI 友好：可接受 axes 句柄）
- ❌ GUI 不内嵌一份体检逻辑
- ✅ 未来 G2/G3/G4 同样只调用，不复制

## 详见

`博士课程-无线/实验3-项目完整性审计与GUI设计规划.md` §2.2~2.5（4-tab 详细设计 + 实现路径 G1~G5）