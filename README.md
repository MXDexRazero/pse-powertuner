# PSE-PowerTuner

沿着 **PowerSettingsExplorer**（第三方电源设置浏览工具）给出的思路——**不走 `powercfg.exe`，
直接调用 `powrprof.dll`**——把处理器性能相关的 31 项隐藏电源设置自动调成三档场景。
核心不是"调用 powercfg"，而是直接调用 Windows 公开的 Power Management API，
这也是本机能生效的唯一路径。

本分支在此之上新增了**中文交互式控制面板**，双击 `运行控制面板.bat` 即用
（完整操作说明见「控制面板使用方法」一节），不想记命令行时派得上用场。

| 档位 | Key | 基底方案 | 适用 |
|---|---|---|---|
| 稳定版 | `balanced-stable` | 平衡 | 日常办公、开发机、虚拟机 |
| 极致版 | `max-perf` | 高性能 | 游戏、渲染、低延迟 |
| 节能版 | `eco` | 节能 | 续航、移动办公 |

## 控制面板使用方法

控制面板是本分支相对上游的主要新增：把全部命令行操作收进一个中文菜单，不必记参数。
**双击 `运行控制面板.bat` 即可**——它会自动检测权限并弹出 UAC 提权，然后进入
`Show-PowerMenu.ps1`。

```powershell
.\运行控制面板.bat            # 双击亦可；非管理员时自动提权
.\运行控制面板.bat -nomouse   # 纯键盘模式（鼠标失灵时的保命开关）
.\Show-PowerMenu.ps1          # 已是管理员时可直接运行（-NoMouse 同上）
```

> `.bat` 只做「管理员检测 + UAC 自提权 + 启动菜单」，中文界面全部由 PowerShell 侧渲染。
> 原因是 cmd 按 OEM 代码页（936）解码批处理，UTF-8 中文必乱码。

### 基本操作

| 操作 | 方式 |
|---|---|
| 选择 | 鼠标直接点选项，或输入序号后回车 |
| 返回上级 | `Esc` 或 `Ctrl+C` |
| 退出程序 | 主菜单选 `0`（在主菜单按 `Esc` / `Ctrl+C` 亦可） |
| 执行确认 | 执行类操作会先打印拼好的**完整命令行**，按 `y` 才真正执行，防误触 |
| 自由输入 | 只有「确认 y/N」和「填值」两种场合需要键盘输入，其余全程点/选 |

菜单顶部会显示**当前是否具备管理员权限**。应用档位、回滚、注册计划任务需要管理员；
只读操作（`-Detect` / `-List` / `-Diff` / 查看备份）不需要。

### 主菜单

| 选项 | 作用 |
|---|---|
| `1` | **一键应用** —— 按硬件自动选档并应用（含电池 DC 档），随后生成 HTML 报告并打开浏览器。日常只用这一项 |
| `2` | **备份菜单** —— 查看备份清单 / 回滚到最近一次备份（回滚前问 `y` 确认） |
| `3` | **所有命令** —— 四级下钻，可执行任何命令，见下 |
| `0` | 退出 |

### 「所有命令」的四级下钻

选 `3` 之后逐级下钻，每一级都能按 `Esc` 回到上一级：

1. **二级 · 选脚本** —— `Apply-PowerProfile.ps1` / `Show-PowerReport.ps1` /
   `Invoke-PowerBench.ps1` / `Rollback-PowerScheme.ps1` / `Install-PowerTuneTask.ps1`，
   外加两项特殊入口：
   - **常用组合**：预设好的完整命令，选中即执行（如「演练 max-perf」）
   - **全部命令说明**：只读，一屏列出所有脚本与参数，不执行任何东西
2. **三级 · 选参数** —— 列出该脚本支持的参数及说明，也有「不带任何参数」这一项。
3. **四级 · 选值 / 填值** —— 枚举型参数（如 `-Profile`）列出全部可选值；
   需填值的参数（如 `-Seconds`）给出输入提示，非法输入会被拒绝并重问。
4. **执行** —— 先显示拼好的命令行，按 `y` 执行，其它键取消。

三个容易踩到的细节：

- 选完 `-Profile` 后会**额外追问一次是否追加 `-IncludeDC`**（是否同时写入电池档）。
- `Invoke-PowerBench.ps1` **只产数据、不产报告**（结果追加到 `reports\bench.csv`）。
  它跑完菜单会追问「是否立即生成图表报告并打开浏览器」——不加这一步很容易
  把末尾的「下一步」提示误读成报告已生成。
- 菜单会自动切到本仓库目录再执行，不需要自己 `cd`。

### 一次典型使用

1. 双击 `运行控制面板.bat` → UAC 确认 → 进入主菜单（顶部会显示目录与管理员状态）
2. 选 `1` 一键应用 → 自动选档应用 → 报告在浏览器中打开
3. 对结果不满意想收回改动：选 `2` → 「回滚到最近一次备份」→ 按 `y` 确认
4. 只想先看看会改成什么、不真正写入：选 `3` → **常用组合** →
   选 `.\Apply-PowerProfile.ps1 -Profile max-perf -DryRun`（写临时方案 → 校验 → 立即删除，不留痕迹）

数据目录统一在 `%ProgramData%\PSE-PowerTuner\`，下分 `backup` / `log` / `reports`。

> 菜单只提供命令**预览**用于确认，不支持在菜单里编辑命令行。要调整参数请在
> 三级/四级菜单里改选，或用「全部命令说明」查清参数后直接跑命令行。

## 为什么必须用 powrprof 而不是 powercfg

本机（多数 OEM 精简电源策略机器同理）的 `powercfg /query` 只认**方案已承载**的设置，
对注册表中存在但方案未实例化的隐藏项一律报「指定的电源方案、子组或设置不存在」。
同一个 GUID 的实测对比：

```
powercfg /query SUB_PROCESSOR be337238-0d82-4146-a960-4f3749d470c7
  → 指定的电源方案、子组或设置不存在

PowerReadACValueIndex(scheme, SUB_PROCESSOR, be337238-...)
  → rc=0, value=2          ← 成功
```

也就是说，**任何纯 powercfg 的调优脚本在这台机器上会把 Turbo / EPP / 核心停放全部静默跳过**。
注册表 `HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-…`（处理器电源管理）
下实际有 **95 项**设置，但 `powercfg` 只肯显示 2 项。

## 快速开始

```powershell
# 以管理员身份启动 PowerShell
cd <本仓库目录>

.\Apply-PowerProfile.ps1 -Detect                 # 1. 只看硬件检测与推荐
.\Apply-PowerProfile.ps1 -List                   # 2. 看三档配置表
.\Apply-PowerProfile.ps1 -Diff max-perf          # 3. 对比当前值 vs 目标值（只读）
.\Apply-PowerProfile.ps1 -Profile max-perf -DryRun -IncludeDC   # 4. 演练，无痕
.\Apply-PowerProfile.ps1 -Profile max-perf -IncludeDC           # 5. 正式应用
```

任何正式应用前都会全量备份到 `%ProgramData%\PSE-PowerTuner\backup\<时间戳>-<标签>\`，
包含每个方案的 `.pow`、`manifest.json`，以及 `values.json`（**原生 API 逐项快照，还原的唯一可靠依据**）。

## 三档差异（AC 交流档）

| 设置 | 稳定版 | 极致版 | 节能版 |
|---|---|---|---|
| `PERFBOOSTMODE` 性能提升模式 | 2 激进 | 2 激进 | 1 启用 |
| `PERFEPP` 能效偏好 | 50 | **0 纯性能** | 80 |
| `CPMINCORES` 最小停放核心% | 25 | **100 禁止停放** | 50 |
| `PROCTHROTTLEMIN` 最小处理器状态% | 5 | **100 锁高频** | 5 |
| `PROCTHROTTLEMAX` 最大处理器状态% | 100 | 100 | 85 |
| `PERFINCPOL` 升频策略 | 0 保守 | **2 常时** | 0 保守 |
| `PERFINCTHRESHOLD` / `PERFDECTHRESHOLD` | 60 / 20 | **20 / 60** | 60 / 20 |
| `PERFLATENCYSENSITIVITY` 延迟敏感度 | 50 | **100** | 0 |
| `PERFHETERO` 异构调度 | 4 优先P核 | 4 优先P核 | 0 自动 |
| `IDLEDISABLE` 空闲禁用（DC） | 0 | — | 1 |
| `IDLEPROMOTE` 空闲深眠阈值 | 60 | **60（电池档也不降）** | 40 |
| `IDLEDEMOTE` 空闲唤醒阈值 | 40 | **40（电池档也不降）** | 20 |
| `IDLEMAX` 最深 C 态上限 | 0 不限制 | 0 不限制 | 0 不限制 |
| `HETEROSCHED` / `HETEROSCHED2` 异构线程调度 | 5 / 2 | 5 / 2 | 5 / 2 |

空闲三项取值照抄 Windows 对应默认方案（高性能 60/40、平衡 60/40、节能 40/20）；
异构调度两项在 Windows 全部方案中取值恒定，本项目不分档改写。
电池档（DC）是独立的一套更保守参数，需加 `-IncludeDC` 才写入。

## 本机实测验证结果

34 项候选设置经「读 → 写 → 回读 → 还原」往返验证：

- **31 项可读可写** → **全部**已编入三档配置
- **3 项只读**（`PERFINCTIME` / `PERFDECTIME` / `PERFTIME`，写入被拒）
- **0 项不可读**（此前记录的「异构调度不可读」是探测脚本 GUID 抄写错误所致，已修正）
- 极致版演练（`-DryRun -IncludeDC`）：**57 项写入全部通过，0 失败**；节能版：**51 项，0 失败**

95 项完整清单见 `_ref\processor-settings.csv`；上述可写性结论可用
`_ref\Test-PwrApi.ps1`（管理员）随时复现，其产物 `writable-test.csv` 为机器专属，已加入 `.gitignore`。

## 文件

| 文件 | 作用 |
|---|---|
| `运行控制面板.bat` | **图形入口**：仅做管理员检测 + UAC 自提权，然后启动控制面板 |
| `Show-PowerMenu.ps1` | **交互式中文控制面板**：键盘 + 鼠标，四级命令树，支持预览与执行 |
| `modules\PowerTune.psm1` | 公共库：powrprof P/Invoke、GUID 表、三档配置、备份/回滚 |
| `Apply-PowerProfile.ps1` | 一键入口：探测 → 选档 → 应用 → 核验；支持 `-DryRun` 演练 |
| `Rollback-PowerScheme.ps1` | 回滚到指定备份或 Windows 默认 |
| `Invoke-PowerBench.ps1` | 基准对照（吞吐 / 频率 / 抖动），纯 .NET，无第三方依赖 |
| `Show-PowerReport.ps1` | HTML 报告：三档差异 + 基准趋势 |
| `Install-PowerTuneTask.ps1` | 计划任务：登录应用 / 插拔电源自适应 |
| `_ref\Test-PwrApi.ps1` | 可写性探测工具，换机器时重跑它刷新白名单（产物 csv 不入库） |
| `_ref\processor-settings.csv` | 处理器电源管理子组下全部 95 项设置清单 |
| `vendor\NOTICE.md` | 第三方组件的溯源与来源说明（**不含任何第三方二进制**，见下） |
| `.github\workflows\release.yml` | 自动发布：推送 `v*` 标签时自动生成 Release 与发布说明（见「发布」） |

## 发布

打标签并推送，Actions 会自动完成发布：

```powershell
git tag v1.0.0
git push origin v1.0.0
```

生成的 Release 包含两部分：

1. **ZIP 资产** —— `pse-powertuner-<tag>.zip`，仓库全部文件打包（不含 `.git`），可直接下载
2. **发布说明** ——
   - GitHub 自动生成的提交摘要
   - 以及本次的**变更文件清单**（对比上一个 tag 的 `git diff --name-status`；
     首个 Release 则列出全部文件）

也可在 Actions 页面手动触发（需填写一个已存在的 tag）。

> 打包用的是 checkout 后的工作区，而不是 `git archive`：`.gitattributes` 里 `.bat` 为
> `eol=crlf`，只有工作区取出的 `.bat` 才是 CRLF；`git archive` 直接读 blob 会还原成 LF，
> 而 cmd 按 OEM 代码页解码 + LF 换行会把多字节内容整段误判成命令。工作流对该项有校验
> （不匹配只告警，不中断发布）。） |

## 换到别的机器

不同硬件暴露的设置集不同（大小核 CPU 才有 `PERFHETERO`；部分 OEM 会裁掉更多项）。
脚本已内建存在性校验：读不到就记为 `Fail` 并跳过，不会写坏方案。要在新机器上刷新白名单：

```powershell
.\_ref\Test-PwrApi.ps1        # 重探测本机可写集合，据此更新模块内的 $Script:Writable
```

## 安全设计

1. **存在性校验**：每项写入后立即回读比对，不一致即判失败，绝不盲写。
2. **全量备份**：`.pow` + `values.json` 双份，值还原走原生 API。
3. **可逆**：改动落在克隆方案上，不动原方案；`-Restore` 一键回出厂。
4. **无痕演练**：`-DryRun` 写临时方案 → 校验 → 立即删除。
5. **日志**：`%ProgramData%\PSE-PowerTuner\log\powertune.log` 记录每项写入结果。

## 已知限制与风险

**极致版把最小处理器状态设为 100% 并禁止核心停放。** 在散热受限的轻薄本上，这会持续高频、
触发温度墙降频，实际表现可能**低于**稳定版。笔记本建议先跑：

```powershell
.\Apply-PowerProfile.ps1 -Profile max-perf -IncludeDC
.\Invoke-PowerBench.ps1 -Label "极致版"
.\Apply-PowerProfile.ps1 -Profile balanced-stable -IncludeDC
.\Invoke-PowerBench.ps1 -Label "稳定版"
.\Show-PowerReport.ps1 -Open     # 看两档的多核吞吐与抖动对比
```

**3 项只读设置**无法调整：`PERFINCTIME`、`PERFDECTIME`、`PERFTIME`（升/降频时间与检查间隔）。

**回滚：**
```powershell
.\Rollback-PowerScheme.ps1 -List      # 看备份
.\Rollback-PowerScheme.ps1            # 回滚最近一次
.\Apply-PowerProfile.ps1 -Restore     # 恢复出厂电源方案
```

⚠️ 注意 `-Restore` 会调用 `powercfg -restoredefaultschemes`，**该命令会删除所有非默认电源方案**。
如果你有自建方案，先 `.\Rollback-PowerScheme.ps1 -List` 确认备份存在再执行。

## 关于 PowerSettingsExplorer

同类工具 **PowerSettingsExplorer**（第三方 Windows 电源设置浏览工具）给了本项目一个关键启发：
它**不走 `powercfg.exe`**，而是直接 P/Invoke `powrprof.dll`。本项目沿用了同一条访问通路。

所用到的都是 **Windows 公开的 Power Management API**（见 `powrprof.h` / Windows SDK 文档），
可通过系统头文件与注册表结构自行验证：

```
PowerEnumerate            PowerGetActiveScheme     PowerSetActiveScheme
PowerReadACValueIndex     PowerWriteACValueIndex   PowerRead/WriteDCValueIndex
PowerReadFriendlyName     PowerReadDescription     PowerWriteSettingAttributes
PowerReadValueMin/Max/Increment      PowerReadPossibleValue
PowerReadDefaultACIndex   PowerReadDefaultDCIndex  PowerDeterminePlatformRole
```

本项目**不调用、不分发** PowerSettingsExplorer 的本体，也未包含其任何二进制、IL 或
反编译产物；全部 PowerShell 代码为自行实现（GUID 与取值语义来自 Windows 注册表
`HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings`）。

> 该工具的许可状态无法确认（归档与二进制内均无许可声明），因此本仓库不再提供其副本。
> 如需获取，请从其官方发布渠道下载，校验值与说明见 `vendor\NOTICE.md`。

## 许可

MIT

