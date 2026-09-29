# 本仓库与上游仓库的差异说明

本文档说明本 fork 相对上游仓库的**全部文件级差异**，以及每处改动的动机与依据。

## 一、基准信息

| 项目 | 内容 |
|---|---|
| 上游仓库 | `Zioove/pse-powertuner` （<https://github.com/Zioove/pse-powertuner>） |
| 对比基准 | 分支 `main`，HEAD 提交 `251ccfa7` |
| 上游最后一次提交 | 2026-09-25 `feat: 归档 PowerSettingsExplorer 原始工具并补充溯源说明` |
| 本 fork | `MXDexRazero/pse-powertuner` （<https://github.com/MXDexRazero/pse-powertuner>） |
| 差异方向 | **本 fork 领先于上游**，上游尚未合并本仓库的改动 |

统计：本地文件 **17** 个，上游文件 **16** 个；完全一致 **2** 项，有差异 **11** 项，本 fork 新增 **4** 项，本 fork 删除 **2** 项，仅存在于上游 **1** 项。

## 二、文件清单与状态总览

| 文件 | 状态 | 上游 | 本地 | 行变化 | 说明 |
|---|---|---|---|---|---|
| `LICENSE` | 一致 | 1064 B | 1064 B | — | 未改动 |
| `_ref/processor-settings.csv` | 一致 | 10650 B | 10650 B | — | 未改动 |
| `.gitattributes` | 修改 | 195 B | 440 B | +5 / -0 | 见下文详解 |
| `.gitignore` | 修改 | 151 B | 273 B | +3 / -0 | 见下文详解 |
| `Apply-PowerProfile.ps1` | 修改 | 9793 B | 9976 B | +5 / -4 | 见下文详解 |
| `Install-PowerTuneTask.ps1` | 修改 | 4651 B | 4654 B | +0 / -0 | 见下文详解 |
| `Invoke-PowerBench.ps1` | 修改 | 8248 B | 10215 B | +84 / -40 | 见下文详解 |
| `README.md` | 修改 | 7983 B | 14414 B | +147 / -30 | 见下文详解 |
| `Rollback-PowerScheme.ps1` | 修改 | 2828 B | 2990 B | +6 / -2 | 见下文详解 |
| `Show-PowerReport.ps1` | 修改 | 8239 B | 8484 B | +12 / -7 | 见下文详解 |
| `_ref/Test-PwrApi.ps1` | 修改 | 6435 B | 7105 B | +8 / -3 | 见下文详解 |
| `modules/PowerTune.psm1` | 修改 | 31032 B | 33141 B | +41 / -13 | 见下文详解 |
| `vendor/NOTICE.md` | 修改 | 1991 B | 2583 B | +38 / -27 | 见下文详解 |
| `.github/workflows/release.yml` | **新增** | — | 4570 B | 全新文件 | 见下文详解 |
| `DIFF-vs-upstream.md` | **新增** | — | 24114 B | 全新文件 | 见下文详解 |
| `Show-PowerMenu.ps1` | **新增** | — | 44246 B | 全新文件 | 见下文详解 |
| `运行控制面板.bat` | **新增** | — | 2815 B | 全新文件 | 见下文详解 |
| `_ref/Push-ViaApi.ps1` | **删除** | 3635 B | — | 已移除 | 见下文详解 |
| `vendor/PowerSettingsExplorer.zip` | **删除** | 36482 B | — | 已移除 | 见下文详解 |
| `_ref/writable-test.csv` | 仅上游有 | 2815 B | — | — | 已按 `.gitignore` 排除，见「四、被排除的文件」 |

### 编码变更（内容无差异）

以下文件**内容完全一致**，差异仅为补齐 UTF-8 BOM：

- `Install-PowerTuneTask.ps1`

**原因**：Windows PowerShell 5.1 按系统 ANSI 代码页（GBK）解码无 BOM 的 UTF-8 脚本，会导致中文注释乱码并触发 `ParserError`。本项目约定所有 `.ps1` / `.psm1` 一律保存为 **UTF-8 with BOM**，此改动是必要修复而非噪声。

## 三、逐文件差异详解

### `.gitattributes`

**规模**：上游 195 字节 → 本地 440 字节，行变化 +5 / -0。

**修复一个新引入的致命缺陷。**

上游没有 `.bat` / `.cmd` 文件，因此规则表里只覆盖了 `.ps1` / `.psm1` / `.md` / `.csv`。
本次新增 `运行控制面板.bat` 后，它会落入兜底规则 `* text=auto eol=lf`，**被 Git 强制转成 LF 换行**。

这与本项目对批处理文件的硬约束直接冲突：

> `.bat` / `.cmd` 必须「纯 ASCII + CRLF + 无 BOM」。cmd 按 OEM 代码页（936）解码脚本，
> 若同时是 LF 换行，会把多字节内容整段误判为命令，表现为满屏刷 `'***' 不是内部或外部命令`。

即：**文件在本机是对的，但一旦 clone 下来就必然损坏**。因此补上两条显式规则把换行钉死：

```gitattributes
*.bat   text eol=crlf
*.cmd   text eol=crlf
```

并附注释说明成因，避免后续被当作冗余规则删掉。

### `.gitignore`

**规模**：上游 151 字节 → 本地 273 字节，行变化 +3 / -0。

新增一条忽略规则：

```gitignore
# 探测脚本产物：机器专属，且「原值」列依赖运行时的激活方案，不入库
_ref/writable-test.csv
```

原因有两点：该 CSV 是 `_ref\Test-PwrApi.ps1` 的**本机专属产物**；且其「原值」列记录的是
「运行探测时当前激活方案」的值，**切换激活方案重跑即含义改变**，不能作为跨机器基线使用。
任何机器上复核可写性都应重跑探测脚本。

### `Apply-PowerProfile.ps1`

**规模**：上游 9793 字节 → 本地 9976 字节，行变化 +5 / -4。

入口脚本，随核心模块的参数扩充做配套调整（`-Diff` 对比输出、档位取值来源注释等），
以保证新加入的空闲/异构调度项能在只读对比与 `-DryRun` 演练中被正确覆盖与展示。

### `Invoke-PowerBench.ps1`

**规模**：上游 8248 字节 → 本地 10215 字节，行变化 +84 / -40。

**修复一个会导致 PowerShell 进程直接被终止的严重缺陷。**

上游实现把 PowerShell `ScriptBlock` 挂到原生 `[Threading.Thread]` 上执行压测负载。
该做法在 Windows PowerShell 5.1 下不可用：原生线程没有 Runspace，`ScriptBlock` 无法在其中执行，
进程会被直接终止（且**没有任何报错输出**），表现为基准测试无法完成。

改为使用 **RunspacePool + `BeginInvoke()` / `EndInvoke()`** —— 这是 PowerShell 5.1 下唯一受支持的
并行执行方式。同时：
- 把负载逻辑抽离为独立的 `$loadScript` 字符串，通过 `AddScript(...).AddArgument(...)` 传参
- 局部变量名改为 `$MyMilliseconds` / `$MyIndex`，避开 PS 5.1「变量大小写不敏感」导致的参数名冲突
（原写法 `$threads` 与管道变量同名，回写时会触发类型转换异常）
- 用 `try/finally` 保证 RunspacePool 与 PowerShell 实例被正确释放

### `README.md`

**规模**：上游 7983 字节 → 本地 14414 字节，行变化 +147 / -30。

随核心模块同步更新对外表述，主要有：

1. **新增「控制面板使用方法」一节**（完整操作指南，非简单提及）：把新增的
   `运行控制面板.bat` 与 `Show-PowerMenu.ps1` 作为本分支主要特色放在显著位置。
   内容包括：三种启动方式（双击 / `-nomouse` 纯键盘 / 直接跑 `.ps1`）、
   基本操作对照表（鼠标点击、序号回车、`Esc` 返回、`y` 确认执行）、
   主菜单四项说明、「所有命令」四级下钻的逐级步骤与三个易踩细节
   （`-Profile` 后追问 `-IncludeDC`、基准脚本只产数据需二次追问生成报告、菜单自动切目录）、
   一次典型使用流程，以及「菜单只提供预览、不支持编辑命令行」的澄清。
   并在开头「文件」表首两行补入这两个文件。
   （上游 README 完全没有提及控制面板——它当时还不存在。）
2. 处理器相关设置数量 `26` → **`31`**，可写结论同步为「**0 项不可读**」
3. 演练写入项数更新：极致版 `47 项` → **`57 项`**，节能版 `41 项` → **`51 项`**，均为 **0 失败**
   （上游未加 `-IncludeDC`，项数统计口径不同）
4. 新增参数对照行：`IDLEPROMOTE` / `IDLEDEMOTE` / `IDLEMAX` / `HETEROSCHED` / `HETEROSCHED2`，
   并注明空闲三项照抄 Windows 对应默认方案、异构调度两项「Windows 全部方案中恒定，不分档改写」
5. 「稳定本」→「**稳定版**」全文用词统一
6. 数据来源说明改写：`writable-test.csv` 明确为**机器专属产物**且已加入 `.gitignore`；
   可写性结论改由 `_ref\Test-PwrApi.ps1`（管理员运行）随时复现
   （原表述会让读者误以为该 CSV 是可跨机器复用的基线）

7. **合规改写**（2026-09-30 审计后）：
   - 开头与「关于 PowerSettingsExplorer」章节**去除逆向措辞**：不再写「逆向出」「阅读其程序集」，
     改为「沿用其思路 / 所用 API 均为 Windows 公开的 Power Management API（`powrprof.h`）」。
   - 删除原「内部数据模型」整段（列 `PwrSetting`、`POWER_DATA_ACCESSOR`、`SchemeTypes` 等
     内部结构，以及 `SaveSettingsAsSctipt` 拼写说明）—— 该段明确以「读取程序集」为依据，
     措辞上易被理解为依赖反编译成果。本项目实际未包含任何 IL 或反编译产物，故一并移除以避免歧义。
   - 删除对已移除归档的引用；「文件」表对应行改为指向 `vendor\NOTICE.md`（来源指引）。

### `Rollback-PowerScheme.ps1`

**规模**：上游 2828 字节 → 本地 2990 字节，行变化 +6 / -2。

回滚脚本，适配新增设置项：回滚时不仅要还原改过的参数，还需覆盖新纳入白名单的 5 项，
避免出现「回滚后仍残留调优值」的情况。

### `Show-PowerReport.ps1`

**规模**：上游 8239 字节 → 本地 8484 字节，行变化 +12 / -7。

报告生成脚本，适配 `PowerTune.psm1` 新增的 5 项设置：在报告表格中正确读取并展示
`IDLEPROMOTE` / `IDLEDEMOTE` / `IDLEMAX` / `HETEROSCHED` / `HETEROSCHED2` 的当前值与目标值。

### `_ref/Test-PwrApi.ps1`

**规模**：上游 6435 字节 → 本地 7105 字节，行变化 +8 / -3。

可写性探测工具，本次修正的核心是**探测脚本自身的 GUID 抄写错误**。

该脚本曾经把手写的两条异构调度 GUID 抄错（前缀误作 `0688` / `0668`，均不在 95 项权威清单中），
导致 `PowerReadACValueIndex` 返回 `rc=2`，上游据此得出「异构调度不可读」的结论。
现已校正为 `_ref/processor-settings.csv` 中的真实 GUID。

**约定**：`_ref/processor-settings.csv`（95 项）是唯一的权威 GUID/名称清单，
任何新增或校对都必须先与之比对，禁止依赖手抄 GUID。

其输出产物 `writable-test.csv` 已加入 `.gitignore`（详见「四、被排除的文件」）。

### `modules/PowerTune.psm1`

**规模**：上游 31032 字节 → 本地 33141 字节，行变化 +41 / -13。

核心配置库，本次改动最大，三处实质性修复/扩充：

1. **新增 5 项设置定义**
   - `HETEROSCHED` `93b8b6dc-0698-4d1c-9ee4-0644e900c85d`（异构线程调度策略）
   - `HETEROSCHED2` `bae08b81-2d5e-4688-ad6a-13243356654b`（短任务线程调度策略）
   - `IDLEPROMOTE` `7b224883-b3cc-4d79-819f-8374152cbe7c`（空闲深眠阈值）
   - `IDLEDEMOTE` `4b92d758-5a24-4851-a470-815d78aee119`（空闲唤醒阈值）
   - `IDLEMAX` `9943e905-9a30-4ec1-9b99-44dd3b76f7a2`（最深 C 态上限）

2. **修正「异构调度不可读」的错误结论**
   上游把 `HETEROSCHED` 归类为「本机不可读」（`V='不可用'`，记录其 `93b8b6dc-…` 不可读）。
   实际是探测脚本 `_ref/Test-PwrApi.ps1` 曾把两条异构调度 GUID 抄错（误抄为 `0688`/`0668` 前缀），
   导致 `PowerReadACValueIndex` 返回 `rc=2`，被误判为不可读。以 `_ref/processor-settings.csv`
   （95 项完整清单）为准校正 GUID 后，该项**可读可写**。

3. **可写白名单 26 项 → 31 项**，三档配置补齐空闲与异构调度取值：
   - `IDLEPROMOTE` / `IDLEDEMOTE`：按 Windows 原生默认方案取值 —— 高性能 60/40、平衡 AC 60/40（DC 40/20）、节能 40/20
   - `IDLEMAX`：Windows 全部方案中恒为 `0`（不限制），故统一 `0`
   - `HETEROSCHED`：Windows 全部方案中恒为 `5`；`HETEROSCHED2`：AC `2` / DC `5` —— 二者在各方案下恒定，故**不分档改写**

   取值原则：所有取值均以本机读出的 Windows 四套默认方案（平衡 `381b4222-…`、高性能 `8c5e7fda-…`、
   节能 `a1841308-…`、卓越性能 `bf0998be-…`）为准，不凭经验臆测。

同时把档位标题「稳定本」修正为「稳定版」（与「极致版 / 节能版」用词统一）。

### `vendor/NOTICE.md`

**规模**：上游 1991 字节 → 本地 2583 字节，行变化 +38 / -27。

由「组件归档说明」改写为「**来源指引**」，配合上一条的合规处置：

- 删除原表中「归档内文件 / 来源 / 用途」等指向本体的描述，改为明确声明
  **本目录不包含任何第三方二进制文件本体**
- 保留并完整记录三份哈希（zip / exe / exe.config），供已自行获取者核验版本
- 新增「为什么不随仓库分发」一节，写明许可状态无法确认的具体依据
- 新增「自行获取与校验」与「合规与联系」两节，并保留权利人的移除通道

### `.github/workflows/release.yml`

**规模**：新增文件，4570 字节。

**全新文件 —— 自动发布工作流。**

上游没有任何 CI 配置。新增它以支持「打 tag 即自动出 Release」，产出两部分：

1. **ZIP 资产**：`pse-powertuner-<tag>.zip`，把仓库全部文件打包（排除 `.git`），作为 Release 资产上传
2. **发布说明**：GitHub 自动生成的提交摘要 + 本次的**变更文件清单**
   （对比上一个 tag 的 `git diff --name-status`；首个 Release 时改为列出全部文件）

实现上的几个关键取舍：

- **打包必须用 checkout 后的工作区，不能用 `git archive`。** `.gitattributes` 里 `.bat` 是
  `eol=crlf`，只有工作区取出的 `.bat` 才是 CRLF；`git archive` 直接读 blob 会还原成 LF，
  而 cmd 按 OEM 代码页解码 + LF 换行会把多字节内容整段误判成命令（本项目踩过的坑）。
  工作流因此对包内 `.bat` 做了 CRLF 校验（不匹配只告警，不中断发布）。
- 触发条件：推送 `v*` 标签；或在 Actions 页面手动触发（需填已存在的 tag）
- 说明中的「GitHub 自动摘要」走 `releases/generate-notes` 接口，取不到时回退到 `git log`
- 使用 runner 上预装的 `gh` CLI 与 `zip`，不引入第三方 Action，避免额外供应链依赖
- `permissions: contents: write` 必须显式声明 —— `GITHUB_TOKEN` 默认只读，不放开则创建 Release 会 403
- 加 `--verify-tag`：tag 不存在时直接失败，避免打错标签时建出一个空 Release

### `DIFF-vs-upstream.md`

**规模**：新增文件，24114 字节。

**全新文件（本文档）。**

上游没有此文档。编写目的是让 fork 的差异**可审计**：把「改了哪些文件、为什么改、
依据是什么、哪些还没验证」集中落盘，而不是散落在对话里。

包含五个部分：① 对比基准（上游仓库 / 分支 / HEAD 提交 SHA）；② 全量文件清单与状态总览；
③ 逐文件差异详解（含动机与取值依据）；④ 被排除的文件及原因；⑤ **未做的验证**（如实列出尚未完成的工作）。

### `Show-PowerMenu.ps1`

**规模**：新增文件，44246 字节。

**全新文件（44 KB）—— 交互式中文控制面板。**

这是上游完全没有的功能。以全屏 TUI 菜单组织全部命令，替代手写命令行：

- 主菜单：`1` 一键运行并测试 / `2` 备份菜单 / `3` 所有命令 / `0` 退出
- 备份二级菜单：`1` 查看备份 / `2` 回滚到最近备份 / `3` 返回上级
- 支持**键盘 + 鼠标**双输入（通过 P/Invoke 读控制台鼠标事件）
- 四级命令树：脚本 → 参数 → 取值 → 预设

实现上有若干针对 Windows PowerShell 5.1 的必要处理，已固化为本项目约定：

| 陷阱 | 处理方式 |
|---|---|
| `Add-Type` 编译 .NET 代码可能被安全策略拦截 | 全部套 `try/catch` 降级，不影响主流程 |
| 禁把 ScriptBlock 挂原生线程 | 并行一律用 RunspacePool（进程会被直接终止） |
| 单元素数组会被赋值拆包，`PSCustomObject.Count` 在 5.1 返回 `$null` | 一律 `@()` 包一层，`$x = @(); $x += @(...)` |
| 含 Add-Type 的脚本无法在本地验证是否编译通过 | 如实标注「未编译验证、需实操确认」 |
| Hashtable 键名撞 .NET 内建属性（`.Values`/`.Keys`/`.Count`）取到的不是键值 | 统一用 `Get-Field $item '键'`，禁止 `$item.键` |
| 鼠标 `dwMousePosition` 是缓冲区绝对坐标，`RawUI.CursorPosition` 是窗口相对坐标，滚动后会错位 | 命中行统一用 `GetConsoleScreenBufferInfo().dwCursorPosition.Y` |

自动化验证方式：把选择序列用管道喂 stdin，
`"2`n1`nx`n3`n3`n" | powershell -NoProfile -File .\Show-PowerMenu.ps1`，
`Read-Host` 会从 stdin 读取，可无交互验证菜单流转。

**修正过时引用**：脚本头部说明、每屏顶部标题栏的管理员提示、以及「全部命令说明」屏，
原先都引用 `Run-PowerTune.bat`。该文件已改名为 `运行控制面板.bat`，旧引用会让用户去运行
一个**不存在的文件**（尤其管理员提示那句是直接显示给用户看的），已全部改正。

### `运行控制面板.bat`

**规模**：新增文件，2815 字节。

**全新文件 —— 图形入口启动器。**

只做两件事：**管理员权限检测 + UAC 自提权**，然后启动 `Show-PowerMenu.ps1`。
中文界面一律交由 PowerShell 侧渲染。

**编码硬约束**：本仓库中 `.bat` / `.cmd` 必须「**纯 ASCII + CRLF 换行 + 无 BOM**」，两条都不能破：

1. cmd 按 OEM 代码页（936）解码脚本，UTF-8 中文会解析成乱码；
2. 若同时是 LF 换行，cmd 会把多字节乱码整段误判为命令，表现为满屏刷
   `'***' 不是内部或外部命令`。

因此该文件内部注释一律使用英文。

**修复一处保命开关失效**：`-nomouse`（鼠标失灵时强制纯键盘）原先只在**未提权**的执行路径
生效。非管理员时脚本会经 UAC 自提权重启自身，而重启语句没有把参数带过去 —— 结果是
提权后 `-nomouse` 被静默丢弃、仍然进入鼠标模式，恰好让这个"鼠标坏了才用"的开关在最需要的
场景下失效。已在提权分支补上参数透传：

```bat
set "ELEV_ARG="
if /i "%~1"=="-nomouse" set "ELEV_ARG=-ArgumentList '-nomouse'"
... Start-Process -FilePath '%~f0' %ELEV_ARG% -Verb RunAs ...
```

同时把注释里的旧文件名 `Run-PowerTune.bat` 改为不指名（该文件已改名，且批处理注释必须纯 ASCII）。

### `_ref/Push-ViaApi.ps1`

**规模**：已从本 fork 中删除（上游为 3635 字节）。

**已从本 fork 中删除**（上游仍保留）。

它在上游的定位是「备用上传通路」：当 `github.com:443` 被网络屏蔽时绕过 git，
直接走 GitHub REST 对象 API 把本地仓库内容推上去（二进制走 base64 编码，
自动以远程当前 HEAD 为父节点追加新提交）。

删除理由有三：

1. **本机不需要这条通路**。`git push` 经系统级 Git Credential Manager 可直接完成认证，
   加上显式代理（`127.0.0.1:7890`）即可正常访问 GitHub，不存在需要绕行的场景。
2. **无法直接复用**。脚本内硬编码了上游作者的个人环境 —— 本地仓库路径
   `C:\Users\hongx\Documents\jiebao\PSE-PowerTuner`、`Owner = 'Zioove'`、
   gh CLI 路径 `C:\Program Files\GitHub CLI\gh.exe`。换人换机器都必须先改这几处，
   留着反而容易误用。
3. **减少凭据相关面**。该脚本会以调用者身份向 GitHub 写入内容，属凭据相关工具；
   在已有正规 git 通路的前提下没有保留价值。

若日后确实遇到 `github.com:443` 不可达，可从上游客仓库或本 fork 的历史提交中取回。

### `vendor/PowerSettingsExplorer.zip`

**规模**：已从本 fork 中删除（上游为 36482 字节）。

**已从本 fork 中删除（合规处置）** —— 这是本次审计中发现的最主要风险点。

归档内含第三方工具的可执行文件 `PowerSettingsExplorer.exe`（99,328 B，.NET 4.5.1 / MSIL / x86，
2017 年构建）及其配置文件。

**风险证据**（均取自文件本身，非推测）：

1. 归档内**无任何许可文件**（无 LICENSE / COPYING / EULA / README）
2. 二进制内**也搜不到任何许可文本或版权署名** —— 连 `vendor/NOTICE.md` 声称的作者
   `Sameer` 在整个二进制里**一字不存**，即该归属信息无法由文件自证
3. 因此它是「作者不明、许可不明」的第三方编译产物，公开放在仓库里即构成
   **复制 + 向公众传播**，许可缺失时存在著作权侵权风险
4. 原 `NOTICE.md` 内部自相矛盾：一边声明「本仓库对其不授予任何再分发许可」，
   一边把文件公开摆在仓库里

需要说明的是，上游 `Zioove/pse-powertuner` **同样分发该归档** —— 风险是继承来的，
但公开 fork 后本仓库同样承担。

**处置方式**：删除本体，把 `vendor/NOTICE.md` 改写为**来源指引** —— 保留 zip 与包内两个文件的
SHA256、参考版本元数据、以及「请从官方渠道自行获取」的说明，并明确指出本目录**不含任何
第三方二进制**。溯源需求完全保留，但不再承担分发第三方著作物的责任。

## 四、被排除的文件

| 文件 | 归属 | 未纳入本 fork 的原因 |
|---|---|---|
| `_ref/Push-ViaApi.ps1` | 上游有、本 fork 已删 | **有意删除**，不是遗漏。理由见「三、逐文件差异详解」。 |
| `vendor/PowerSettingsExplorer.zip` | 上游有、本 fork 已删 | **有意删除**，不是遗漏。理由见「三、逐文件差异详解」。 |
| `_ref/writable-test.csv` | 仅上游有 | `_ref\Test-PwrApi.ps1` 的本机专属产物：① 记录的是本机可写集合；②「原值」列依赖运行探测时的激活方案，**换机器或换档位即失真**。已加入 `.gitignore` 不再入库。需在任意机器上复核可写性时，重跑 `_ref\Test-PwrApi.ps1` （管理员）即可 |
| `pse-powertuner-main.zip` | 仅本地有 | GitHub 下载的上游源码归档快照，属临时产物，非仓库内容，已按约定排除 |
| `.workbuddy/` | 仅本地有 | 工作区辅助目录，非项目代码 |

> **注意**：上游 `main` 分支历史中仍保留了 `_ref/writable-test.csv`。通过网页上传无法删除文件，若需彻底剔除，请在克隆后执行 `git rm --cached _ref/writable-test.csv && git commit`。

## 五、未做的验证

以下工作**尚未完成**，如实记录以免误解：

- **C# / P/Invoke 代码未经编译验证**：本机安全策略会拦截运行时编译加载 .NET（`Add-Type`）与 `csc.exe`，因此 `Show-PowerMenu.ps1` 中的控制台鼠标输入、坐标获取等原生调用**未能在本机实际编译验证**。脚本已做 `try/catch` 降级处理，但需在开放环境下实机确认。
- **三档配置的实机跑分未开展**：`Invoke-PowerBench.ps1` 需要在切换各档位后实测单/多核吞吐与调度抖动，本次未执行，README 中的可行性结论沿用上游表述。
- **「31 项可写」为本机（Windows 11 + 该机型 BIOS）结论**：换机器后 PLATFORM 相关设置可能不同，请以本机重跑 `_ref\Test-PwrApi.ps1` 的结果为准。

## 六、合规处置记录

2026-09-30 对「本 fork 相对上游」做了著作权与合规审计，结果如下。

| 项目 | 结论 | 处置 |
|---|---|---|
| `vendor\PowerSettingsExplorer.zip` | **高风险**：第三方编译产物，归档与二进制内均无许可声明，无版权署名 | **已删除**，改为来源指引 |
| README / psm1 中的逆向措辞 | 低-中风险：未含 IL 或反编译产物，但「阅读其程序集」的措辞易生歧义 | **已软化** |
| MIT 许可合规 | **合规**：上游 LICENSE（MIT, (c) 2026 Zioove）原样保留，满足「保留版权与许可声明」条件 | 无需处置 |
| 第三方许可代码混入 | **未发现**：全仓库扫描 GPL / AGPL / LGPL / Apache / BSD / MPL 许可头，0 命中 | 无需处置 |
| 个人信息泄露 | **未发现**：扫描邮箱、`C:\Users\<用户名>` 路径、`gh*_` token、`AKIA` 密钥，0 命中 | 无需处置 |

> 说明：以上为工程视角的合规评估，不构成法律意见。
