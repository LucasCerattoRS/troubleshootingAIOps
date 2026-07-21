# framework/collectors/generic/health.ps1
#
# Windows pair of health.sh. Collects general system health from a /health
# endpoint and prints structured JSON.
#
# Usage: .\health.ps1 [-TargetHost localhost:3000] [-TimeoutSec 5]
#
# NOTE: the parameter is -TargetHost, not -Host: $Host is a reserved PowerShell
# automatic variable and must not be shadowed.
# ASCII-only on purpose (see analyzer.ps1 header for the PS 5.1 / BOM reason).

[CmdletBinding()]
param(
  [string] $TargetHost = "localhost:3000",
  [int]    $TimeoutSec = 5
)

$now         = [DateTimeOffset]::UtcNow
$collectedAt = $now.ToUnixTimeSeconds()
$iso         = $now.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

try {
  $resp = Invoke-RestMethod -Uri "http://$TargetHost/health" -TimeoutSec $TimeoutSec
} catch {
  [ordered]@{
    collected_at = $collectedAt
    timestamp    = $iso
    source       = "health-check"
    status       = "error"
    error        = "Health endpoint unreachable or invalid JSON"
    detail       = $_.Exception.Message
    host         = $TargetHost
  } | ConvertTo-Json -Depth 6
  exit 1
}

$status = switch ($resp.status) {
  "healthy"  { "ok" }
  "degraded" { "degraded" }
  "down"     { "down" }
  default    { "unknown" }
}

[ordered]@{
  collected_at = $collectedAt
  timestamp    = $iso
  source       = "health-check"
  host         = $TargetHost
  status       = $status
  details      = $resp
} | ConvertTo-Json -Depth 8

exit 0
