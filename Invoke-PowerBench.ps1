<#
.SYNOPSIS
    三档配置对照基准：CPU 单/多核吞吐 + 频率驻留 + 调度抖动
.DESCRIPTION
    纯 .NET 实现，不依赖第三方工具。
    - 吞吐：多线程浮点/内存混合负载
    - 频率：CallNtPowerInformation 读取各逻辑处理器实时 MHz
    - 抖动：1ms 忙等切片的间隔偏差（近似唤醒延迟/DPC 影响）
.EXAMPLE
    .\Invoke-PowerBench.ps1 -Seconds 20 -Label "极致版"
#>
[CmdletBinding()]
param(
    [int]$Seconds = 20,
    [string]$Label = (Get-Date -Format 'HHmmss')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $root 'modules\PowerTune.psm1') -Force
$work = Get-WorkRoot

#region ── 实时频率读取 ─────────────────────────────────────────────────

$freqSrc = @'
using System;
using System.Runtime.InteropServices;

public static class PseCpuFreq
{
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESSOR_POWER_INFORMATION
    {
        public uint Number;
        public uint MaxMhz;
        public uint CurrentMhz;
        public uint MhzLimit;
        public uint MaxIdleState;
        public uint CurrentIdleState;
    }

    [DllImport("powrprof.dll", SetLastError = true)]
    private static extern uint CallNtPowerInformation(
        int InformationLevel, IntPtr lpInputBuffer, uint nInputBufferSize,
        IntPtr lpOutputBuffer, uint nOutputBufferSize);

    public static uint[] Current()
    {
        int n = Environment.ProcessorCount;
        int sz = Marshal.SizeOf(typeof(PROCESSOR_POWER_INFORMATION));
        IntPtr p = Marshal.AllocHGlobal(sz * n);
        try
        {
            uint r = CallNtPowerInformation(11, IntPtr.Zero, 0, p, (uint)(sz * n));
            if (r != 0) return new uint[0];
            uint[] res = new uint[n];
            for (int i = 0; i < n; i++)
            {
                IntPtr q = (IntPtr)((long)p + (long)i * sz);
                PROCESSOR_POWER_INFORMATION s =
                    (PROCESSOR_POWER_INFORMATION)Marshal.PtrToStructure(
                        q, typeof(PROCESSOR_POWER_INFORMATION));
                res[i] = s.CurrentMhz;
            }
            return res;
        }
        finally { Marshal.FreeHGlobal(p); }
    }
}
'@

$hasFreq = $true
try { Add-Type -TypeDefinition $freqSrc -ErrorAction Stop }
catch {
    $hasFreq = $false
    Write-TuneLog "频率读取不可用（$($_.Exception.Message)），跳过频率统计" 'WARN'
}

#endregion

#region ── 负载与抖动测量 ───────────────────────────────────────────────

$loadScript = @'
param([int]$MyMilliseconds, [int]$MyIndex)

$acc = 0.0
$ops = [long]0
$buf = New-Object 'double[]' 512
for ($i = 0; $i -lt 512; $i++) { $buf[$i] = $i * 0.5 }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt $MyMilliseconds) {
    for ($i = 1; $i -le 10000; $i++) {
        $acc += [Math]::Sqrt($i) * 1.000001
        $buf[$i % 512] = $acc * 0.999999
        if ($acc -gt 1e12) { $acc = 0.0 }
    }
    $ops += 10000
}
$sw.Stop()

[pscustomobject]@{ Index = $MyIndex; Ops = $ops; ElapsedMs = $sw.ElapsedMilliseconds }
'@

function Invoke-CpuLoad {
    <#
        多线程混合负载：浮点 + 内存访问，返回总操作数与耗时。
        实现说明：Windows PowerShell 5.1 中把 ScriptBlock 挂到原生
        [Threading.Thread] 上执行会直接终止进程（该线程没有 Runspace），
        因此这里改用 RunspacePool —— 5.1 下唯一受支持的并行方式。
    #>
    param(
        [Parameter(Mandatory)][int]$Threads,
        [Parameter(Mandatory)][int]$Milliseconds
    )

    $pool = $null
    $jobs = New-Object 'System.Collections.Generic.List[object]'
    try {
        $pool = [runspacefactory]::CreateRunspacePool($Threads, $Threads)
        $pool.ThreadOptions = 'ReuseThread'
        $pool.Open()

        $sw = [Diagnostics.Stopwatch]::StartNew()
        for ($i = 0; $i -lt $Threads; $i++) {
            $ps = [powershell]::Create()
            $ps.RunspacePool = $pool
            $null = $ps.AddScript($loadScript).AddArgument($Milliseconds).AddArgument($i)
            $jobs.Add([pscustomobject]@{
                PS     = $ps
                Handle = $ps.BeginInvoke()
            })
        }

        $total = [long]0
        $done  = 0
        foreach ($j in $jobs) {
            $out = $j.PS.EndInvoke($j.Handle)
            foreach ($r in $out) { $total += [long]$r.Ops; $done++ }
        }
        $sw.Stop()
    }
    finally {
        foreach ($j in $jobs) { if ($j.PS) { $j.PS.Dispose() } }
        if ($pool) { $pool.Close(); $pool.Dispose() }
    }

    if ($done -lt $Threads) {
        Write-TuneLog "负载线程仅 $done/$Threads 个返回结果，吞吐数据可能偏低" 'WARN'
    }

    [pscustomobject]@{
        Threads    = $Threads
        ElapsedMs  = $sw.ElapsedMilliseconds
        Workers    = $done
        Ops        = $total
        MopsPerSec = if ($sw.ElapsedMilliseconds -gt 0) {
            [math]::Round($total / ($sw.ElapsedMilliseconds / 1000.0) / 1e6, 2)
        } else { 0 }
    }
}

function Measure-SchedulerJitter {
    <#  1ms 忙等切片，统计实际间隔与目标的偏差  #>
    param([int]$Milliseconds = 3000)

    $samples = New-Object 'System.Collections.Generic.List[double]'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $last = 0.0
    while ($sw.ElapsedMilliseconds -lt $Milliseconds) {
        $spin = [Diagnostics.Stopwatch]::StartNew()
        while ($spin.Elapsed.TotalMilliseconds -lt 1.0) { }
        $now = $sw.Elapsed.TotalMilliseconds
        $samples.Add([Math]::Abs(($now - $last) - 1.0))
        $last = $now
    }
    if ($samples.Count -eq 0) { return [pscustomobject]@{ P50 = 0; P99 = 0; Max = 0 } }
    $sorted = @($samples | Sort-Object)
    $p50 = [int][math]::Floor($sorted.Count * 0.50)
    $p99 = [Math]::Min([int][math]::Floor($sorted.Count * 0.99), $sorted.Count - 1)
    [pscustomobject]@{
        P50 = [math]::Round($sorted[$p50], 3)
        P99 = [math]::Round($sorted[$p99], 3)
        Max = [math]::Round($sorted[-1], 3)
    }
}

function Measure-AverageFrequency {
    param([int]$Samples = 20, [int]$IntervalMs = 100)
    if (-not $hasFreq) { return 0 }
    # 类型名必须写全（uint 是 C# 别名，PowerShell 只认 System.UInt32）
    $all = New-Object 'System.Collections.Generic.List[System.UInt32]'
    for ($i = 0; $i -lt $Samples; $i++) {
        $r = [PseCpuFreq]::Current()
        foreach ($v in $r) { if ($v -gt 0) { $all.Add($v) } }
        Start-Sleep -Milliseconds $IntervalMs
    }
    if ($all.Count -eq 0) { return 0 }
    [math]::Round(($all | Measure-Object -Average).Average)
}

#endregion

#region ── 执行 ─────────────────────────────────────────────────────────

$scheme     = Get-ActiveScheme
$schemeName = (Get-SchemeList)[$scheme]
$logical    = [Environment]::ProcessorCount

Write-Host "`n═══ 基准测试：$Label ═══" -ForegroundColor Cyan
Write-Host "当前方案: $schemeName ($scheme)" -ForegroundColor DarkGray
Write-Host "逻辑处理器: $logical · 每项负载 ${Seconds}s" -ForegroundColor DarkGray

# PS 5.1 的 Write-Host 会 trim 掉结尾的 `n，且 Write-Host '' 完全不输出；
# 空行只能靠下一条 Write-Host 的前导 `n 来产生。
Write-Host "`n[1/4] 单线程吞吐 ..." -ForegroundColor Yellow
$single = Invoke-CpuLoad -Threads 1 -Milliseconds ($Seconds * 1000)

Write-Host "[2/4] 全核吞吐（$logical 线程）..." -ForegroundColor Yellow
$multi = Invoke-CpuLoad -Threads $logical -Milliseconds ($Seconds * 1000)

Write-Host '[3/4] 调度抖动 ...' -ForegroundColor Yellow
$jitter = Measure-SchedulerJitter -Milliseconds 3000

Write-Host '[4/4] 平均频率 ...' -ForegroundColor Yellow
$freqAvg = Measure-AverageFrequency

$result = [pscustomobject]@{
    Timestamp   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    Label       = $Label
    Scheme      = $schemeName
    SchemeGuid  = $scheme
    SingleScore = $single.MopsPerSec
    MultiScore  = $multi.MopsPerSec
    Scaling     = if ($single.MopsPerSec -gt 0) { [math]::Round($multi.MopsPerSec / $single.MopsPerSec, 2) } else { 0 }
    FreqAvgMHz  = $freqAvg
    JitterP50ms = $jitter.P50
    JitterP99ms = $jitter.P99
    JitterMaxms = $jitter.Max
}

Write-Host "`n═══ 结果 ═══" -ForegroundColor Cyan
# 就地渲染：若让 Format-List 的对象流到管道，被上级脚本 & 调用时会被当成
# 返回值，污染调用方的退出码判断（Out-Host 不影响 $result 本身）。
$result | Format-List | Out-Host

$csv = Join-Path $work 'reports\bench.csv'
$result | Export-Csv -Path $csv -Append -NoTypeInformation -Encoding UTF8
Write-Host "已追加记录到 $csv" -ForegroundColor DarkGray

# 与历史同方案对比
# 同样避免单行结果被拆包后 .Count 失效的坑
$hist = @()
$hist += @(Import-Csv $csv -ErrorAction SilentlyContinue | Where-Object { $_.SchemeGuid -eq $scheme })
if ($hist.Count -gt 1) {
    $prev = $hist[-2]
    Write-Host '与上次同方案对比：' -ForegroundColor Yellow
    foreach ($f in @('SingleScore','MultiScore','FreqAvgMHz','JitterP99ms')) {
        $d = [double]$result.$f - [double]$prev.$f
        $sign = if ($d -gt 0) { '+' } else { '' }
        Write-Host ('  {0,-14} {1,9} -> {2,9}  ({3}{4})' -f $f, $prev.$f, $result.$f, $sign, [math]::Round($d, 2))
    }
}

# ⚠️ 本脚本【只做基准并把结果追加到 reports\bench.csv】，不会生成 HTML 报告。
# 此前这里写成「生成图表报告: .\Show-PowerReport.ps1 -Open」，措辞像"已经生成"，
# 与菜单随后的「执行完成（退出码 0）」连读会被误认为报告已产出（实测踩过）。
# 故改为明确的「下一步（未自动执行）」措辞。
Write-Host "`n下一步（本脚本未自动执行）: .\Show-PowerReport.ps1 -Open    # 生成 HTML 报告并打开" -ForegroundColor DarkGray

#endregion
