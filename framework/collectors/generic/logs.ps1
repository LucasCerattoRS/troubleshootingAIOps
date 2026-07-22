# framework/collectors/generic/logs.ps1
#
# Windows pair of logs.sh. Extracts ERROR/WARN lines from the last N lines of a log file.
# Usage: .\logs.ps1 -File <path> [-Lines 100] [-Pattern 'ERROR|WARN']
#
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $File,
  [int]    $Lines   = 100,
  [string] $Pattern = "ERROR|WARN"
)

$now         = [DateTimeOffset]::UtcNow
$collectedAt = $now.ToUnixTimeSeconds()
$iso         = $now.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

if (-not (Test-Path -LiteralPath $File)) {
  [ordered]@{
    collected_at = $collectedAt
    timestamp    = $iso
    source       = "logs"
    status       = "error"
    error        = "log file not found: $File"
    file         = $File
  } | ConvertTo-Json -Depth 5
  exit 1
}

$matched = @()
try {
  $matched = @(
    Get-Content -LiteralPath $File -Tail $Lines -Encoding UTF8 |
      Where-Object { $_ -match $Pattern } |
      ForEach-Object {
        $level = if ($_ -match "ERROR") { "ERROR" } elseif ($_ -match "WARN") { "WARN" } else { "INFO" }
        [ordered]@{ level = $level; message = $_; timestamp = $null }
      }
  )
} catch { }

[ordered]@{
  collected_at  = $collectedAt
  timestamp     = $iso
  source        = "logs"
  file          = $File
  lines_scanned = $Lines
  matched       = $matched.Count
  logs          = $matched
} | ConvertTo-Json -Depth 6

exit 0
