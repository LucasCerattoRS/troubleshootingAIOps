# framework/collectors/generic/events.ps1
#
# Windows pair of events.sh. Recent git activity in a repo (commits/deploys in window).
# Usage: .\events.ps1 [-Repo <path>] [-SinceMinutes 180]
#
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [string] $Repo         = ".",
  [int]    $SinceMinutes = 180
)

$now         = [DateTimeOffset]::UtcNow
$collectedAt = $now.ToUnixTimeSeconds()
$iso         = $now.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

function Write-CollectorError([string] $message) {
  [ordered]@{
    collected_at = $collectedAt
    timestamp    = $iso
    source       = "events"
    status       = "error"
    error        = $message
    repo         = $Repo
  } | ConvertTo-Json -Depth 5
  exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-CollectorError "git not found" }

& git -C $Repo rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) { Write-CollectorError "not a git repository: $Repo" }

$events = @()
try {
  $raw = & git -C $Repo log --since="$SinceMinutes minutes ago" --pretty=format:"%H|%cI|%s"
  if ($raw) {
    $events = @(
      $raw | ForEach-Object {
        $parts = $_ -split "\|", 3
        if ($parts.Count -ge 3) {
          [ordered]@{
            type      = "COMMIT"
            sha       = $parts[0].Substring(0, [Math]::Min(8, $parts[0].Length))
            timestamp = $parts[1]
            message   = $parts[2]
          }
        }
      }
    )
  }
} catch { }

[ordered]@{
  collected_at  = $collectedAt
  timestamp     = $iso
  source        = "events"
  repo          = $Repo
  since_minutes = $SinceMinutes
  count         = $events.Count
  events        = $events
} | ConvertTo-Json -Depth 6

exit 0
