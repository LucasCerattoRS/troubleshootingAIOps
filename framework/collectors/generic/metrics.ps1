# framework/collectors/generic/metrics.ps1
#
# Windows pair of metrics.sh. Collects CPU / memory / disk usage.
# Usage: .\metrics.ps1 [-DriveLetter C]
#
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [string] $DriveLetter = "C"
)

$now         = [DateTimeOffset]::UtcNow
$collectedAt = $now.ToUnixTimeSeconds()
$iso         = $now.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

$cpuPercent  = $null
$memPercent  = $null
$diskPercent = $null

try {
  $cpu = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
  if ($null -ne $cpu) { $cpuPercent = [int]$cpu }
} catch { }

try {
  $os = Get-CimInstance Win32_OperatingSystem
  if ($os.TotalVisibleMemorySize -gt 0) {
    $used = $os.TotalVisibleMemorySize - $os.FreePhysicalMemory
    $memPercent = [int](100 * $used / $os.TotalVisibleMemorySize)
  }
} catch { }

try {
  $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($DriveLetter):'"
  if ($disk -and $disk.Size -gt 0) {
    $usedDisk = $disk.Size - $disk.FreeSpace
    $diskPercent = [int](100 * $usedDisk / $disk.Size)
  }
} catch { }

[ordered]@{
  collected_at   = $collectedAt
  timestamp      = $iso
  source         = "metrics"
  mount          = "$($DriveLetter):"
  cpu_percent    = $cpuPercent
  memory_percent = $memPercent
  disk_percent   = $diskPercent
} | ConvertTo-Json -Depth 5

exit 0
