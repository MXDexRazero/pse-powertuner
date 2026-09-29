<#
.SYNOPSIS
    PSE-PowerTuner 交互式控制面板（中文菜单，鼠标点击 + 键盘序号双通道）
.DESCRIPTION
    由根目录 Run-PowerTune.bat 以管理员身份启动；也可直接
    .\Show-PowerMenu.ps1 运行（非管理员时部分功能会失败）。

    主菜单：
      1  一键测试   Apply-PowerProfile.ps1 -Profile auto -IncludeDC
                         Show-PowerReport.ps1 -Open
      2  备份菜单（二级） 查看备份 / 回滚到最近备份 / 返回上级菜单
      3  所有命令（二级） 脚本 → 参数（三级） → 取值（四级），逐级选择并执行
      0  退出程序

    鼠标模式：启动时开启（关闭 QuickEdit 以便接收点击），
    退出/异常/中断时用 try/finally 还原原来的控制台模式。
.EXAMPLE
    .\Show-PowerMenu.ps1
#>
[CmdletBinding()]
param(
    # 保命开关：跳过鼠标模式，只走纯键盘（鼠标输入异常时使用）
    [switch]$NoMouse
)

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $root

try { $Host.UI.RawUI.WindowTitle = 'PSE-PowerTuner 控制面板' } catch { }

#region ── 基础工具 ──────────────────────────────────────────────────────

function Test-AdminRole {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 输入被重定向（非交互/自动化）时为 $true：此时不做鼠标、不等待、不执行
function Test-RedirectedInput { [Console]::IsInputRedirected }

# 菜单数据结构（脚本项 / 参数项 / 取值项 / 预设项）一律是 hashtable，
# 取字段必须走本函数（索引访问），不要写 $item.XXX。
#
# ⚠️ 原因：hashtable 自带 Keys / Values / Count / SyncRoot / IsReadOnly 等内建属性，
#    点号访问会优先命中【属性】而不是同名【键】——$h.Values 拿到的是"全体字段值的集合"，
#    对任何哈希表都恒为真。此前四级菜单正是因此把参数条目自身的
#    Prompt / Name / Desc / Param / Kind 当成了选项列出来。
#    凡键名可能与内建属性同名（Values / Keys / Count ...）都必须用索引访问。
function Get-Field {
    param($Item, [string]$Key)
    if ($null -eq $Item) { return $null }
    if ($Item -is [System.Collections.IDictionary]) { return $Item[$Key] }
    $prop = $Item.PSObject.Properties[$Key]
    if ($prop) { return $prop.Value }
    return $null
}

#endregion

#region ── 鼠标支持（P/Invoke 控制台 API）───────────────────────────────
#
# 控制台默认开 QuickEdit，点击会被解释为"选中文本"而不上报鼠标事件，
# 因此必须：置 ENABLE_EXTENDED_FLAGS(0x0080) + 清 ENABLE_QUICK_EDIT_MODE(0x0040)
#           + 置 ENABLE_MOUSE_INPUT(0x0010)。
# 原模式在启动时保存，退出时 finally 还原，只影响当前控制台窗口。
#
# ⚠️ 重要设计约束：这里【只用 P/Invoke 处理鼠标】，键盘一律交给 .NET 自己的
#    [Console]::ReadKey()。原因：此前用 P/Invoke 读 KEY_EVENT_RECORD 时，
#    bKeyDown(Win32 BOOL) 未按 4 字节封送，导致字段偏移整体差 2 字节——
#    UnicodeChar 实际读到的是 wVirtualScanCode（小键盘 3 的扫描码 0x51 = 'Q'），
#    回车也读不到 VK_RETURN。键盘交给托管 API 后，这类封送问题不可能再发生；
#    即便鼠标部分失效，键盘也始终可用。

$script:MouseEnabled    = $false
$script:OrigConsoleMode = 0
$script:TrustKeyDown    = $true     # bKeyDown 封送是否可信（见 PeekEventType 注释）
$script:KeyUpDiscarded  = 0

if (-not (Test-RedirectedInput) -and -not $NoMouse) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class PseConsoleInput
{
    const int STD_INPUT_HANDLE  = -10;
    const int STD_OUTPUT_HANDLE = -11;
    const uint ENABLE_MOUSE_INPUT     = 0x0010;
    const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
    const uint ENABLE_EXTENDED_FLAGS  = 0x0080;
    const ushort KEY_EVENT   = 0x0001;
    const ushort MOUSE_EVENT = 0x0002;
    const uint FROM_LEFT_1ST_BUTTON_PRESSED = 0x0001;

    [StructLayout(LayoutKind.Sequential)]
    public struct COORD { public short X; public short Y; }

    // 键盘结构体已不再使用（键盘交给托管 [Console]::ReadKey）。
    // 这里保留只为确定 union 的大小；字段一律用显式偏移，避免封送歧义。
    [StructLayout(LayoutKind.Explicit)]
    public struct KEY_EVENT_RECORD {
        [FieldOffset(0)][MarshalAs(UnmanagedType.Bool)] public bool bKeyDown;
        [FieldOffset(4)]  public ushort wRepeatCount;
        [FieldOffset(6)]  public ushort wVirtualKeyCode;
        [FieldOffset(8)]  public ushort wVirtualScanCode;
        [FieldOffset(10)] public char   UnicodeChar;
        [FieldOffset(12)] public uint   dwControlKeyState;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSE_EVENT_RECORD {
        public COORD dwMousePosition;
        public uint  dwButtonState;
        public uint  dwControlKeyState;
        public uint  dwEventFlags;
    }

    // union 从偏移 4 开始（EventType 是 WORD，union 内首个成员是 BOOL，按 4 对齐）
    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT_RECORD {
        [FieldOffset(0)] public ushort EventType;
        [FieldOffset(4)] public KEY_EVENT_RECORD   KeyEvent;
        [FieldOffset(4)] public MOUSE_EVENT_RECORD MouseEvent;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SMALL_RECT { public short Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct CONSOLE_SCREEN_BUFFER_INFO {
        public COORD      dwSize;
        public COORD      dwCursorPosition;
        public ushort     wAttributes;
        public SMALL_RECT srWindow;
        public COORD      dwMaximumWindowSize;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetConsoleMode(IntPtr h, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetConsoleScreenBufferInfo(IntPtr h, out CONSOLE_SCREEN_BUFFER_INFO lpInfo);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetConsoleMode(IntPtr h, uint dwMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint lpcNumberOfEvents);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool PeekConsoleInput(IntPtr h, out INPUT_RECORD lpBuffer,
                                        uint nLength, out uint lpNumberOfEventsRead);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadConsoleInput(IntPtr h, out INPUT_RECORD lpBuffer,
                                        uint nLength, out uint lpNumberOfEventsRead);

    public static uint GetMode() {
        uint m = 0;
        GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), out m);
        return m;
    }

    // 幂等：可反复调用。托管 [Console]::ReadKey() 内部会 SetConsoleMode 改来改去，
    // 有可能把 QuickEdit 恢复成"开启"，导致鼠标点击又被当成框选文本。
    // 因此每次等待输入前都重新断言一次。
    public static void EnableMouse() {
        IntPtr h = GetStdHandle(STD_INPUT_HANDLE);
        uint m; GetConsoleMode(h, out m);
        m |= ENABLE_EXTENDED_FLAGS;
        m &= ~ENABLE_QUICK_EDIT_MODE;
        m |= ENABLE_MOUSE_INPUT;
        SetConsoleMode(h, m);
    }

    public static void Restore(uint mode) {
        SetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), mode);
    }

    // 关键：鼠标点击坐标是【屏幕缓冲区绝对坐标】，而 PowerShell 的
    // $Host.UI.RawUI.CursorPosition.Y 是【窗口相对坐标】。缓冲区一旦滚动，
    // 两者会差一个 srWindow.Top，点击就会命中错误的行（表现为"鼠标失效"）。
    // 因此命中行必须用这里的绝对坐标来记录。失败时返回 -1。
    public static int GetCursorRowAbs()
    {
        IntPtr h = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO bi;
        if (!GetConsoleScreenBufferInfo(h, out bi)) return -1;
        return bi.dwCursorPosition.Y;
    }

    public static int GetWindowTop()
    {
        IntPtr h = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO bi;
        if (!GetConsoleScreenBufferInfo(h, out bi)) return 0;
        return bi.srWindow.Top;
    }

    // 非阻塞偷看队首事件类型：
    //   0 = 无事件
    //   1 = 键盘【按下】   → 可交给托管 ReadKey
    //   2 = 鼠标事件       → 自己消费，判定是否左键点击
    //   3 = 键盘【抬起】   → 必须自己丢弃（见下）
    //   4 = 焦点/窗口变化等 → 自己丢弃
    //
    // ⚠️ 两个坑：
    //   1. 不能用 [Console]::KeyAvailable 判空：.NET 检查时会把队首非按键事件
    //      （含鼠标）直接消费并丢弃，鼠标永远读不到。
    //   2. 必须区分按下/抬起：ReadKey 遇到抬起事件会丢弃它并【继续阻塞等待
    //      下一次按键】，期间到达的鼠标事件同样被 .NET 丢弃 → 表现为
    //      "用过一次键盘后鼠标就再也点不动"。所以抬起事件要由我们丢掉。
    public static int PeekEventType()
    {
        IntPtr h = GetStdHandle(STD_INPUT_HANDLE);
        uint pending;
        if (!GetNumberOfConsoleInputEvents(h, out pending) || pending == 0) return 0;

        INPUT_RECORD rec; uint n;
        if (!PeekConsoleInput(h, out rec, 1, out n) || n == 0) return 0;

        if (rec.EventType == KEY_EVENT)   return rec.KeyEvent.bKeyDown ? 1 : 3;
        if (rec.EventType == MOUSE_EVENT) return 2;
        return 4;
    }

    // 消费队首事件：若是"鼠标左键点击"返回 "M:<x>:<y>"，否则返回 null（已丢弃）
    public static string ReadMouseClick()
    {
        IntPtr h = GetStdHandle(STD_INPUT_HANDLE);
        INPUT_RECORD rec; uint n;
        if (!ReadConsoleInput(h, out rec, 1, out n) || n == 0) return null;

        if (rec.EventType == MOUSE_EVENT) {
            bool pressed = (rec.MouseEvent.dwButtonState & FROM_LEFT_1ST_BUTTON_PRESSED) != 0;
            bool isClick = rec.MouseEvent.dwEventFlags == 0;
            if (pressed && isClick) {
                return "M:" + rec.MouseEvent.dwMousePosition.X + ":" + rec.MouseEvent.dwMousePosition.Y;
            }
        }
        return null;
    }
}
'@ -Language CSharp -ErrorAction Stop

        $script:OrigConsoleMode = [PseConsoleInput]::GetMode()
        [PseConsoleInput]::EnableMouse()
        $script:MouseEnabled = $true
    } catch {
        # 编译失败 / 无控制台（ISE 等）→ 自动退回纯键盘，并明确告知用户
        $script:MouseEnabled = $false
        Write-Host "  [提示] 鼠标模式初始化失败，已退回键盘模式：$($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '         菜单功能不受影响，只是不能用鼠标点击。' -ForegroundColor DarkGray
    }
}

# 命中行必须取"屏幕缓冲区绝对行"，才能和鼠标点击坐标（同为绝对坐标）比较。
# $Host.UI.RawUI.CursorPosition.Y 是窗口相对值，缓冲区滚动后会整体错位。
function Get-CursorRow {
    if ($script:MouseEnabled) {
        $r = [PseConsoleInput]::GetCursorRowAbs()
        if ($r -ge 0) { return $r }
    }
    try { return $Host.UI.RawUI.CursorPosition.Y } catch { return 0 }
}

# 键盘：全部走托管 API [Console]::ReadKey()，不经过 P/Invoke。
# 之前用 P/Invoke 读 KEY_EVENT_RECORD 因封送偏差导致按键全错，
# 托管 API 由 .NET 保证正确（含小键盘、退格、回车、Ctrl+C）。
function Read-KeyboardLine {
    $sb = ''
    while ($true) {
        $k = [Console]::ReadKey($true)          # $true = 拦截、不自动回显，下面统一回显
        if ($k.Key -eq [ConsoleKey]::Enter)  { [Console]::Write("`r`n"); return @{ Kind = 'key'; Text = $sb } }
        if ($k.Key -eq [ConsoleKey]::Escape) { [Console]::Write("`r`n"); return @{ Kind = 'key'; Text = "`e" } }
        if ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control)) {
            [Console]::Write("`r`n"); return @{ Kind = 'key'; Text = [string][char]3 }
        }
        if ($k.Key -eq [ConsoleKey]::Backspace) {
            if ($sb.Length -gt 0) {
                $sb = $sb.Substring(0, $sb.Length - 1)
                [Console]::Write("`b `b")
            }
            continue
        }
        $c = $k.KeyChar
        if ($c -ne [char]0 -and -not [char]::IsControl($c)) {
            $sb += $c
            [Console]::Write($c)
        }
    }
}

# 统一输入入口：@{ Kind='key'; Text=... } 或 @{ Kind='mouse'; X=..; Y=.. }
function Read-ConsoleInput {
    if (-not $script:MouseEnabled) {
        $s = Read-Host
        if ($null -eq $s) { $s = '' }
        return @{ Kind = 'key'; Text = $s }
    }
    # 每次等待前重新断言鼠标模式：ReadKey 可能把 QuickEdit 恢复成开启（见 EnableMouse 注释）
    if ($script:MouseEnabled) { [PseConsoleInput]::EnableMouse() }
    if ($script:MouseEnabled -and $env:PSE_MOUSE_DEBUG) {
        $m = [PseConsoleInput]::GetMode()
        Write-Host ("  [DEBUG] consoleMode=0x{0:X4} QuickEdit={1} MouseInput={2}" -f $m,
                    [bool]($m -band 0x40), [bool]($m -band 0x10)) -ForegroundColor Magenta
    }

    # 事件判定全部走 P/Invoke（见 PeekEventType 注释）：
    # 一旦用 [Console]::KeyAvailable，鼠标事件会被 .NET 悄悄丢弃。
    while ($true) {
        $t = [PseConsoleInput]::PeekEventType()
        if ($t -eq 1 -or ($t -eq 3 -and -not $script:TrustKeyDown)) {
            # 队首是"按键按下" → 托管读取；（TrustKeyDown=$false 时不再区分抬起）
            $r = Read-KeyboardLine
            $script:KeyUpDiscarded = 0
            if ($script:MouseEnabled) { [PseConsoleInput]::EnableMouse() }   # 读完立刻自愈
            return $r
        }
        if ($t -eq 2) {                                      # 鼠标事件 → 自己消费
            $m = [PseConsoleInput]::ReadMouseClick()
            if ($m) {
                $p = $m -split ':'
                return @{ Kind = 'mouse'; X = [int]$p[1]; Y = [int]$p[2] }
            }
            continue
        }
        if ($t -eq 3) {                                      # 按键抬起 → 自己丢弃
            $script:KeyUpDiscarded++
            # 兜底：若 bKeyDown 封送不可靠（永远读不到"按下"），丢弃 40 次后放弃区分，
            # 保证键盘不会彻底失效。正常情况下成功读键会清零，这里永不触发。
            if ($script:KeyUpDiscarded -gt 40) { $script:TrustKeyDown = $false }
            [void][PseConsoleInput]::ReadMouseClick()
            continue
        }
        if ($t -gt 0) {                                      # 焦点/窗口变化等 → 自己丢弃
            [void][PseConsoleInput]::ReadMouseClick()
            continue
        }
        Start-Sleep -Milliseconds 20
    }
}

# 只接受键盘的输入（确认 y/n、自由输入等），鼠标点击会被忽略并重问
function Read-Choice {
    param(
        [string]$Prompt = '  请输入序号',
        [switch]$KeysOnly
    )
    while ($true) {
        Write-Host $Prompt -ForegroundColor White
        $r = Read-ConsoleInput
        if ($r.Kind -eq 'key') { return $r.Text.Trim() }
        if (-not $KeysOnly) { return '' }
        Write-Host '  （此处需要键盘输入，鼠标点击无效）' -ForegroundColor DarkGray
    }
}

#endregion

#region ── 显示与执行 ────────────────────────────────────────────────────

function Show-Header {
    param([string]$Title)
    try { Clear-Host } catch { }
    $isAdmin = Test-AdminRole
    Write-Host "`n  ══════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "   $Title" -ForegroundColor Cyan
    Write-Host "  ══════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "   目录    : $root" -ForegroundColor DarkGray
    if ($isAdmin) {
        Write-Host "   管理员  : 是" -ForegroundColor Green
    } else {
        Write-Host "   管理员  : 否 —— 应用/回滚会失败，请以管理员身份运行 Run-PowerTune.bat" -ForegroundColor Red
    }
    if ($script:MouseEnabled) {
        Write-Host "   操作    : 鼠标直接点选项，或输入序号后回车（Esc/Ctrl+C = 返回上级）" -ForegroundColor DarkGray
    }
    Write-Host "  ──────────────────────────────────────────────────────" -ForegroundColor DarkGray
}

# 普通 @{} 的枚举顺序不等于插入顺序，直接拼会拼出 "-DryRun -Profile max-perf" 这种乱序。
# 这里固定为：带值参数在前、开关在后，且 -IncludeDC 永远排在最后（须跟在 -Profile <profile> 之后）。
function Get-ParamText {
    param([hashtable]$Params)
    $named = @(); $switches = @()
    foreach ($k in $Params.Keys) {
        if ($Params[$k] -is [bool] -and $Params[$k]) { $switches += "-$k" }
        else                                         { $named   += "-$k $($Params[$k])" }
    }
    $switches = @($switches | Where-Object { $_ -ne '-IncludeDC' })
    if ($Params.ContainsKey('IncludeDC') -and $Params['IncludeDC']) { $switches += '-IncludeDC' }
    return (@($named) + @($switches) -join ' ')
}

# 用 & 调用同级脚本：已验证子脚本内的 exit 只结束子脚本，不会终止本菜单会话，
# 且 $LASTEXITCODE 能正确回传，因此无需另起 powershell 进程。
#
# 参数必须用【哈希表 splatting】传递，不能用数组 splatting：
# 数组 splatting（& $p @('-Open')）对 PowerShell 命令是按【位置】绑定“值”，
# '-Open' 会被当成第 0 个位置参数的实参 → "找不到接受实际参数 -Open 的位置形式参数"。
# 数组 splatting 只对原生 exe 才是 argv 逐个展开。
function Invoke-Tune {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [hashtable]$Params = @{}
    )
    $p = Join-Path $root $ScriptName
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host "`n  [错误] 找不到脚本：$p" -ForegroundColor Red
        return 1
    }
    Write-Host "`n  > .\$ScriptName $(Get-ParamText $Params)`n" -ForegroundColor DarkGray

    # 子脚本写到管道的对象（例如 Invoke-PowerBench 的 Format-List）必须在这里就地消费：
    # 否则它们会混进本函数的输出流，调用方拿到的「退出码」变成一串 Format*Data 对象，
    # 随后的 "-eq 0" 也永远为假。Out-Host 就地渲染，顺序与 Write-Host 一致。
    #
    # $LASTEXITCODE 会跨调用残留（上次原生命令失败的值），调用前先清零，
    # 否则子脚本没显式 exit 时也会误报上一次的失败码。
    $global:LASTEXITCODE = 0
    try {
        if ($Params.Count -gt 0) { & $p @Params | Out-Host } else { & $p | Out-Host }
    } catch {
        Write-Host "`n  [错误] $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
    if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) { return $LASTEXITCODE }
    return 0
}

# 输入被重定向（非交互/自动化）时直接跳过等待，否则会卡住或空转
function Wait-Enter {
    Write-Host "  ──────────────────────────────────────────────────────" -ForegroundColor DarkGray
    if (Test-RedirectedInput) { return }
    Write-Host '  按回车键继续（也可点击任意位置）' -ForegroundColor DarkGray
    [void](Read-ConsoleInput)
}

# 通用列表菜单：鼠标点击命中行，或键盘输入序号；选 0 / Esc / Ctrl+C 返回 $null
function Select-From {
    param(
        [string]$Title,
        [array]$Items,
        [string]$BackLabel = '返回上级菜单'
    )
    while ($true) {
        Show-Header $Title
        $hits = @()
        $i = 0
        foreach ($it in $Items) {
            $i++
            # 脚本项用 Label，参数项用 Name，取值项只有 Label
            # 一律经 Get-Field 索引访问（见该函数注释：点号会被 hashtable 内建属性遮蔽）
            $label = if (Get-Field $it 'Label') { Get-Field $it 'Label' } else { Get-Field $it 'Name' }
            $desc  = Get-Field $it 'Desc'
            $r0 = Get-CursorRow
            Write-Host ("   [{0}]  {1}" -f $i, $label) -ForegroundColor White
            $r1 = Get-CursorRow
            if ($desc) {
                Write-Host "        $desc" -ForegroundColor DarkGray
                $r1 = Get-CursorRow
            }
            $hits += @{ Row0 = $r0; Row1 = ($r1 - 1); Index = $i }
        }
        $r0 = Get-CursorRow
        Write-Host "   [0]  $BackLabel" -ForegroundColor White
        $hits += @{ Row0 = $r0; Row1 = (Get-CursorRow - 1); Index = 0 }

        Write-Host "`n  请输入序号后回车，或直接点击上面任意一行："
        $res = Read-ConsoleInput

        if ($res.Kind -eq 'mouse') {
            $hit = $null
            foreach ($h in $hits) {
                if ($res.Y -ge $h.Row0 -and $res.Y -le $h.Row1) { $hit = $h; break }
            }
            if ($null -ne $hit) {
                if ($hit.Index -eq 0) { return $null }
                return $Items[$hit.Index - 1]
            }
            # 排障用：set PSE_MOUSE_DEBUG=1 后，点击空白处会打印点击坐标与可命中行区间
            if ($env:PSE_MOUSE_DEBUG) {
                $ranges = ($hits | ForEach-Object { "$($_.Row0)-$($_.Row1)" }) -join ', '
                $top = if ($script:MouseEnabled) { [PseConsoleInput]::GetWindowTop() } else { 'n/a' }
                Write-Host "  [DEBUG] 点击 X=$($res.X) Y=$($res.Y)；可命中行: $ranges；windowTop=$top" -ForegroundColor Magenta
                Start-Sleep -Seconds 3
            }
            continue   # 点空白处：重画菜单
        }

        $c = $res.Text.Trim()
        if ($c -eq "`e" -or $c -eq [string][char]3) { return $null }   # Esc / Ctrl+C = 返回上级
        if ($c -eq '0') { return $null }
        # EOF（stdin 已耗尽）时 Read-Host 会不停返回空串，若不退出就会空转刷屏
        if ($c -eq '' -and (Test-RedirectedInput)) { return $null }
        $n = 0
        if ([int]::TryParse($c, [ref]$n) -and $n -ge 1 -and $n -le $Items.Count) { return $Items[$n - 1] }
        Write-Host "`n  无效输入：$c" -ForegroundColor Red
        if (-not (Test-RedirectedInput)) { Start-Sleep -Seconds 1 }
    }
}

#endregion

#region ── 只读清单 ──────────────────────────────────────────────────────

# 注意：PS 5.1 下 Write-Host '' 完全不输出（连空行都没有），所以分段靠 Show-Section 的前导 `n
function Show-Section  { param([string]$Text) Write-Host "`n  ── $Text " -ForegroundColor Cyan }
function Show-Script   { param([string]$Name, [string]$Desc) Write-Host ("  {0,-30} {1}" -f $Name, $Desc) -ForegroundColor Yellow }
# 第一列（参数名）必须保持纯 ASCII：-f 的宽度按字符数算，而中文在控制台是双宽，
# 含中文的参数名会让后面的说明整体前移。中文只允许出现在第二列（说明）。
function Show-Arg      { param([string]$Arg,  [string]$Desc) Write-Host ("      {0,-35} {1}" -f $Arg, $Desc) -ForegroundColor Gray }
function Show-Note     { param([string]$Text) Write-Host "      $Text" -ForegroundColor DarkGray }
function Show-Example  { param([string]$Cmd,  [string]$Desc) Write-Host ("      {0,-52} {1}" -f $Cmd, $Desc) -ForegroundColor Gray }

function Show-CommandList {
    Show-Header '所有命令'
    Write-Host '  下列命令均在本仓库目录下执行（菜单已自动切到该目录）。' -ForegroundColor DarkGray
    Write-Host '  数据目录：%ProgramData%\PSE-PowerTuner\  （backup / log / reports）' -ForegroundColor DarkGray

    Show-Section '主入口（需管理员，写入前自动备份）'
    Show-Script '.\Apply-PowerProfile.ps1' '按档位写入电源设置，核心脚本'
    Show-Arg '-Profile <profile>' 'auto | balanced-stable | max-perf | eco；默认 auto（按硬件自动选档）'
    Show-Arg '-IncludeDC'      '同时写入电池(DC)档；不加则只写交流(AC)档'
    Show-Arg '-Detect'         '只做硬件检测与推荐档，只读，不修改任何设置'
    Show-Arg '-List'           '打印三档配置对照表（AC/DC 全量目标值）'
    Show-Arg '-Diff <profile>' '对比「当前值 vs 目标值」，只读（profile 不能为 auto）'
    Show-Arg '-DryRun'         '演练：写临时方案 → 回读校验 → 立即删除，不留痕迹'
    Show-Arg '-NoActivate'     '写入设置但不切换当前激活方案'
    Show-Arg '-SkipBackup'     '跳过写入前的自动备份（不建议）'
    Show-Arg '-Restore'        '恢复 Windows 出厂电源方案'
    Show-Arg '-RestoreFrom <dir>'  '从指定备份目录导入方案与数值'

    Show-Section '报告'
    Show-Script '.\Show-PowerReport.ps1' '生成 HTML 报告：当前值 vs 三档 + 基准历史 + 备份记录'
    Show-Arg '-Open' '生成后用默认浏览器打开'

    Show-Section '基准测试'
    Show-Script '.\Invoke-PowerBench.ps1' 'CPU 单/多核吞吐 + 频率驻留 + 调度抖动（纯 .NET，无第三方依赖）'
    Show-Arg '-Seconds <N>'   '每档测试时长，默认 20 秒'
    Show-Arg '-Label <text>'  '结果标签，默认当前时间 HHmmss'
    Show-Note '结果追加到 reports\bench.csv，报告页会读取'

    Show-Section '备份 / 回滚（需管理员）'
    Show-Script '.\Rollback-PowerScheme.ps1' '从备份导入电源方案'
    Show-Arg '-List'             '列出全部备份（时间、方案数）'
    Show-Arg '-Index <N>'        '回滚到倒数第 N 个备份，默认 1（最近一次）'
    Show-Arg '-BackupDir <dir>'  '从指定备份目录回滚'
    Show-Arg '-Defaults'         '直接恢复出厂电源方案'

    Show-Section '自动化（需管理员）'
    Show-Script '.\Install-PowerTuneTask.ps1' '注册计划任务（以 SYSTEM 运行）'
    Show-Arg '-Mode OnLogon'  '登录时应用推荐档（默认）'
    Show-Arg '-Mode Adaptive' '插电=极致版 / 电池=节能版'
    Show-Arg '-Mode Hourly'   '每小时核验一次'
    Show-Arg '-Remove'        '卸载全部已注册任务'

    Show-Section '启动器'
    Show-Script '.\Run-PowerTune.bat'   '双击入口：非管理员自动 UAC 提权并打开本菜单（内容纯 ASCII）'
    Show-Script '.\Show-PowerMenu.ps1'  '本交互菜单本体（也可直接运行，需管理员）'

    Show-Section '常用组合'
    Show-Example '.\Apply-PowerProfile.ps1 -Profile max-perf -DryRun' '演练后再决定是否应用'
    Show-Example '.\Apply-PowerProfile.ps1 -Profile auto -IncludeDC'  '应用推荐档（含电池档）'
    Show-Example '.\Invoke-PowerBench.ps1 -Seconds 20 -Label max-perf' '跑一次基准（标签建议用 ASCII，避免列宽错位）'
    Show-Example '.\Rollback-PowerScheme.ps1'                         '回滚到最近一次备份'
}

#endregion

#region ── 命令树：脚本(二级) → 参数(三级) → 取值(四级) → 执行 ────────────
#
# 三级菜单中每一项的形态（决定下一步行为）：
#   Switch   开关参数，选中后直接执行
#   Values   有枚举取值 → 进入四级菜单让用户选值；WithDC 时选完再问是否追加 -IncludeDC
#   Prompt   需要自由输入（Kind: int / path / string）
#   NoParam  不带任何参数直接执行

$CmdTree = @(
    @{
        Script = 'Apply-PowerProfile.ps1'
        Desc   = '按档位写入电源设置，核心脚本（需管理员，写入前自动备份）'
        Params = @(
            @{ Name = '-Profile <profile>'; Desc = 'auto | balanced-stable | max-perf | eco；默认 auto（按硬件自动选档）'; Param = 'Profile'; Values = @('auto','balanced-stable','max-perf','eco'); WithDC = $true }
            @{ Name = '-IncludeDC';         Desc = '同时写入电池(DC)档；须与 -Profile 配合，写在 -Profile <profile> 之后'; Param = 'IncludeDC'; Switch = $true }
            @{ Name = '-Detect';            Desc = '只做硬件检测与推荐档，只读，不修改任何设置'; Param = 'Detect'; Switch = $true }
            @{ Name = '-List';              Desc = '打印三档配置对照表（AC/DC 全量目标值）'; Param = 'List'; Switch = $true }
            @{ Name = '-Diff <profile>';    Desc = '对比「当前值 vs 目标值」，只读（取值不能为 auto）'; Param = 'Diff'; Values = @('balanced-stable','max-perf','eco') }
            @{ Name = '-DryRun';            Desc = '演练：写临时方案 → 回读校验 → 立即删除，不留痕迹'; Param = 'DryRun'; Switch = $true }
            @{ Name = '-NoActivate';        Desc = '写入设置但不切换当前激活方案'; Param = 'NoActivate'; Switch = $true }
            @{ Name = '-SkipBackup';        Desc = '跳过写入前的自动备份（不建议）'; Param = 'SkipBackup'; Switch = $true }
            @{ Name = '-Restore';           Desc = '恢复 Windows 出厂电源方案'; Param = 'Restore'; Switch = $true }
            @{ Name = '-RestoreFrom <dir>'; Desc = '从指定备份目录导入方案与数值'; Param = 'RestoreFrom'; Prompt = '备份目录的完整路径'; Kind = 'path' }
        )
    },
    @{
        Script = 'Show-PowerReport.ps1'
        Desc   = '生成 HTML 报告：当前值 vs 三档 + 基准历史 + 备份记录'
        Params = @(
            @{ Name = '-Open';            Desc = '生成后用默认浏览器打开'; Param = 'Open'; Switch = $true }
            @{ Name = '（不带任何参数）'; Desc = '只生成报告文件，不打开浏览器'; NoParam = $true }
        )
    },
    @{
        Script = 'Invoke-PowerBench.ps1'
        Desc   = 'CPU 单/多核吞吐 + 频率驻留 + 调度抖动（纯 .NET，无第三方依赖）'
        # 只产数据不产报告：执行成功后由菜单追问是否接着生成 HTML 报告
        ThenReport = $true
        Params = @(
            @{ Name = '-Seconds <N>';    Desc = '每档测试时长，默认 20 秒'; Param = 'Seconds'; Prompt = '测试时长（秒，整数）'; Kind = 'int' }
            @{ Name = '-Label <text>';   Desc = '结果标签，默认当前时间 HHmmss'; Param = 'Label'; Prompt = '结果标签（建议用 ASCII）'; Kind = 'string' }
            @{ Name = '（不带任何参数）'; Desc = '用默认值跑一次，结果追加到 reports\bench.csv'; NoParam = $true }
        )
    },
    @{
        Script = 'Rollback-PowerScheme.ps1'
        Desc   = '从备份导入电源方案（需管理员）'
        Params = @(
            @{ Name = '-List';            Desc = '列出全部备份（时间、方案数）'; Param = 'List'; Switch = $true }
            @{ Name = '-Index <N>';       Desc = '回滚到倒数第 N 个备份，默认 1（最近一次）'; Param = 'Index'; Prompt = '倒数第几个备份（1 = 最近一次）'; Kind = 'int' }
            @{ Name = '-BackupDir <dir>'; Desc = '从指定备份目录回滚'; Param = 'BackupDir'; Prompt = '备份目录的完整路径'; Kind = 'path' }
            @{ Name = '-Defaults';        Desc = '直接恢复出厂电源方案'; Param = 'Defaults'; Switch = $true }
        )
    },
    @{
        Script = 'Install-PowerTuneTask.ps1'
        Desc   = '注册计划任务（以 SYSTEM 运行，需管理员）'
        Params = @(
            @{ Name = '-Mode <mode>'; Desc = 'OnLogon | Adaptive | Hourly'; Param = 'Mode'; Values = @('OnLogon','Adaptive','Hourly') }
            @{ Name = '-Remove';      Desc = '卸载全部已注册任务'; Param = 'Remove'; Switch = $true }
        )
    }
)

$PresetItems = @(
    @{ Label = '.\Apply-PowerProfile.ps1 -Profile max-perf -DryRun';   Desc = '演练：写入临时方案校验后立即删除'; Script = 'Apply-PowerProfile.ps1'; Params = @{ Profile = 'max-perf'; DryRun = $true } }
    @{ Label = '.\Apply-PowerProfile.ps1 -Profile auto -IncludeDC';    Desc = '应用推荐档，含电池(DC)档';       Script = 'Apply-PowerProfile.ps1'; Params = @{ Profile = 'auto'; IncludeDC = $true } }
    @{ Label = '.\Invoke-PowerBench.ps1 -Seconds 20 -Label max-perf';  Desc = '跑一次基准（20 秒），跑完可接着生成报告'; Script = 'Invoke-PowerBench.ps1'; Params = @{ Seconds = 20; Label = 'max-perf' }; ThenReport = $true }
    @{ Label = '.\Rollback-PowerScheme.ps1';                           Desc = '回滚到最近一次备份';             Script = 'Rollback-PowerScheme.ps1'; Params = @{} }
)

$CmdMenuItems = @()
foreach ($s in $CmdTree) {
    $s['Label'] = ".\$(Get-Field $s 'Script')"
    $s['Kind']  = 'script'
    $CmdMenuItems += $s
}
$CmdMenuItems += @{ Label = '常用组合';     Desc = '直接执行预设好的完整命令';         Kind = 'preset'; Items = $PresetItems }
$CmdMenuItems += @{ Label = '全部命令说明'; Desc = '一屏列出所有脚本与参数（只读，不执行）'; Kind = 'doc' }

# 先预览完整命令行，按 y 才真正执行（避免误触）
#
# $ThenReport：针对"只产数据、不产报告"的脚本（如 Invoke-PowerBench.ps1）。
# 它跑完只把结果追加到 bench.csv，报告要另跑 Show-PowerReport.ps1。
# 若不加这一步追问，用户看到脚本末尾的「下一步: Show-PowerReport.ps1」提示
# 加上菜单的「执行完成（退出码 0）」，很容易误以为报告已经生成。
function Invoke-Confirmed {
    param([string]$Script, [hashtable]$Params, [switch]$ThenReport)
    Write-Host "`n  即将执行：" -ForegroundColor Yellow
    Write-Host ("  .\$Script $(Get-ParamText $Params)".TrimEnd()) -ForegroundColor Cyan
    if (Test-RedirectedInput) {
        Write-Host "`n  输入被重定向（非交互环境），已跳过执行。" -ForegroundColor DarkGray
        return
    }
    $ok = Read-Choice '  按 y 执行，其它键取消（Esc 取消）' -KeysOnly
    if ($ok -ne 'y' -and $ok -ne 'Y') {
        Write-Host "`n  已取消。" -ForegroundColor DarkGray
        Wait-Enter
        return
    }
    $code = Invoke-Tune $Script -Params $Params
    if ($code -eq 0) { Write-Host "`n  执行完成（退出码 0）。" -ForegroundColor Green }
    else              { Write-Host "`n  返回非零退出码 $code，请看上方输出。" -ForegroundColor Yellow }

    if ($ThenReport -and $code -eq 0) {
        $go = Read-Choice '  是否立即生成图表报告并打开浏览器？y = 生成，其它键跳过' -KeysOnly
        if ($go -eq 'y' -or $go -eq 'Y') {
            $cRep = Invoke-Tune 'Show-PowerReport.ps1' -Params @{ Open = $true }
            if ($cRep -eq 0) { Write-Host "`n  报告已生成并已用默认浏览器打开。" -ForegroundColor Green }
            else              { Write-Host "`n  报告生成失败（退出码 $cRep），请看上方输出。" -ForegroundColor Yellow }
        } else {
            Write-Host "`n  已跳过报告生成。可随时执行：.\Show-PowerReport.ps1 -Open" -ForegroundColor DarkGray
        }
    }
    Wait-Enter
}

# 三级菜单：列出某脚本的全部参数
function Invoke-ScriptMenu {
    param([hashtable]$ScriptItem)
    # 字段一律经 Get-Field 索引访问（hashtable 内建属性会遮蔽同名键，见 Get-Field 注释）
    $scriptName = Get-Field $ScriptItem 'Script'
    $thenReport = [bool](Get-Field $ScriptItem 'ThenReport')
    while ($true) {
        $param = Select-From -Title (Get-Field $ScriptItem 'Label') `
                             -Items (Get-Field $ScriptItem 'Params') -BackLabel '返回上级菜单'
        if ($null -eq $param) { return }

        if (Get-Field $param 'Switch') {
            $p = @{}; $p[(Get-Field $param 'Param')] = $true
            Invoke-Confirmed -Script $scriptName -Params $p -ThenReport:$thenReport
            continue
        }

        if (Get-Field $param 'NoParam') {
            Invoke-Confirmed -Script $scriptName -Params @{} -ThenReport:$thenReport
            continue
        }

        # 四级菜单：枚举取值。
        # ⚠️ 早先写成点号 $param.Values，拿到的是 Hashtable 自带的 Values 属性
        #    （全体字段值的集合，恒为真），于是把条目自身的 Prompt/Name/Desc/Param/Kind
        #    当成了菜单选项——表现为「四级菜单显示的选项完全不对」。
        $values = Get-Field $param 'Values'
        if ($values) {
            $vals = @()
            foreach ($v in @($values)) { $vals += @{ Label = $v } }
            $picked = Select-From -Title "$(Get-Field $ScriptItem 'Label')  $(Get-Field $param 'Name')" `
                                  -Items $vals -BackLabel '返回上级菜单'
            if ($null -eq $picked) { continue }
            $p = @{}; $p[(Get-Field $param 'Param')] = (Get-Field $picked 'Label')
            if (Get-Field $param 'WithDC') {
                $dc = Read-Choice '  是否追加 -IncludeDC（同时写入电池档）？y 追加，其它键不追加' -KeysOnly
                if ($dc -eq 'y' -or $dc -eq 'Y') { $p['IncludeDC'] = $true }
            }
            Invoke-Confirmed -Script $scriptName -Params $p -ThenReport:$thenReport
            continue
        }

        $prompt = Get-Field $param 'Prompt'
        if ($prompt) {                             # 自由输入（不进四级菜单）
            $raw = Read-Choice "  $prompt（Esc 取消）" -KeysOnly
            if ($raw -eq '' -or $raw -eq "`e" -or $raw -eq [string][char]3) {
                Write-Host "`n  已取消。" -ForegroundColor DarkGray; Wait-Enter; continue
            }
            $val = $raw
            $kind = Get-Field $param 'Kind'
            if ($kind -eq 'int') {
                $n = 0
                if (-not [int]::TryParse($raw, [ref]$n)) {
                    Write-Host "`n  「$raw」不是整数，已取消。" -ForegroundColor Red; Wait-Enter; continue
                }
                $val = $n
            } elseif ($kind -eq 'path') {
                $val = $raw.Trim('"')
                if (-not (Test-Path -LiteralPath $val)) {
                    Write-Host "`n  路径不存在：$val" -ForegroundColor Red; Wait-Enter; continue
                }
            }
            $p = @{}; $p[(Get-Field $param 'Param')] = $val
            Invoke-Confirmed -Script $scriptName -Params $p -ThenReport:$thenReport
            continue
        }

        # 兜底：条目四种形态都不是（命令树写漏了字段），明确报错，
        # 而不是静默重画菜单让人以为"点了没反应"
        Write-Host "`n  [内部错误] 参数条目缺少 Switch / NoParam / Values / Prompt 之一：$(Get-Field $param 'Name')" -ForegroundColor Red
        Wait-Enter
    }
}

# 二级菜单：列出全部脚本
function Invoke-CommandMenu {
    while ($true) {
        $it = Select-From -Title '所有命令' -Items $CmdMenuItems -BackLabel '返回主菜单'
        if ($null -eq $it) { return }
        switch (Get-Field $it 'Kind') {
            'preset' {
                $preset = Select-From -Title '常用组合' -Items (Get-Field $it 'Items') -BackLabel '返回上级菜单'
                if ($null -eq $preset) { continue }
                Invoke-Confirmed -Script (Get-Field $preset 'Script') `
                                 -Params (Get-Field $preset 'Params') `
                                 -ThenReport:([bool](Get-Field $preset 'ThenReport'))
            }
            'doc' { Show-CommandList; Wait-Enter }
            default { Invoke-ScriptMenu $it }
        }
    }
}

#endregion

#region ── 主菜单 ────────────────────────────────────────────────────────

function Invoke-BackupMenu {
    $items = @(
        @{ Id = '1'; Label = '查看备份';       Desc = '.\Rollback-PowerScheme.ps1 -List' }
        @{ Id = '2'; Label = '回滚到最近备份'; Desc = '.\Rollback-PowerScheme.ps1' }
    )
    while ($true) {
        $it = Select-From -Title '备份菜单' -Items $items -BackLabel '返回上级菜单'
        if ($null -eq $it) { return }
        switch (Get-Field $it 'Id') {
            '1' {
                Show-Header '查看备份'
                [void](Invoke-Tune 'Rollback-PowerScheme.ps1' -Params @{ List = $true })
                Wait-Enter
            }
            '2' {
                Show-Header '回滚到最近备份'
                $ok = Read-Choice '  确认回滚到最近一次备份？输入 y 继续，其它键取消' -KeysOnly
                if ($ok -eq 'y' -or $ok -eq 'Y') {
                    $code = Invoke-Tune 'Rollback-PowerScheme.ps1'
                    if ($code -eq 0) { Write-Host "`n  回滚完成。" -ForegroundColor Green }
                    else              { Write-Host "`n  回滚未成功（退出码 $code）。可能是暂无备份。" -ForegroundColor Yellow }
                } else {
                    Write-Host "`n  已取消。" -ForegroundColor DarkGray
                }
                Wait-Enter
            }
        }
    }
}

$MainItems = @(
    @{ Id = '1'; Label = '一键测试'; Desc = "1)  .\Apply-PowerProfile.ps1 -Profile auto -IncludeDC`n        2)  .\Show-PowerReport.ps1 -Open" }
    @{ Id = '2'; Label = '备份菜单';       Desc = '查看备份 / 回滚到最近备份' }
    @{ Id = '3'; Label = '所有命令';       Desc = '脚本 → 参数 → 取值，逐级选择并执行' }
)

$running = $true
try {
    while ($running) {
        $sel = Select-From -Title 'PSE-PowerTuner 控制面板' -Items $MainItems -BackLabel '退出程序'
        if ($null -eq $sel) { $running = $false; break }

        switch (Get-Field $sel 'Id') {
            '1' {
                Show-Header '一键测试'
                Write-Host '  [1/2] 应用推荐档（AC + DC）…' -ForegroundColor Yellow
                $cApply  = Invoke-Tune 'Apply-PowerProfile.ps1' -Params @{ Profile = 'auto'; IncludeDC = $true }
                Write-Host "`n  [2/2] 生成电源配置报告并打开…" -ForegroundColor Yellow
                $cReport = Invoke-Tune 'Show-PowerReport.ps1' -Params @{ Open = $true }
                if ($cApply -eq 0 -and $cReport -eq 0) {
                    Write-Host "`n  全部完成：应用退出码 $cApply，报告退出码 $cReport" -ForegroundColor Green
                } else {
                    Write-Host "`n  完成但存在非零退出码：应用 $cApply，报告 $cReport" -ForegroundColor Yellow
                }
                Wait-Enter
            }
            '2' { Invoke-BackupMenu }
            '3' { Invoke-CommandMenu }
        }
    }
} finally {
    # 任何退出路径（正常退出 / 异常 / 中断）都还原控制台模式（QuickEdit 等）
    if ($script:MouseEnabled) {
        try { [PseConsoleInput]::Restore($script:OrigConsoleMode) } catch { }
    }
}

Write-Host "`n  已退出程序。`n" -ForegroundColor DarkGray
exit 0

#endregion
