# examples/sistema-rh/collectors/express-health.ps1
#
# Windows pair of express-health.sh. Collects Express RH health from /health:
# server status, DB pool, memory, uptime. Prints structured JSON.
#
# Usage: .\express-health.ps1 [-TargetHost localhost:3000] [-TimeoutSec 5]
#
# NOTE: parameter is -TargetHost ($Host is a reserved automatic variable).
# ASCII-only on purpose (PS 5.1 / BOM — see analyzer.ps1 header).

[CmdletBinding()]
param(
  [string] $TargetHost = "localhost:3000",
  [int]    $TimeoutSec = 5
)

$now         = [DateTimeOffset]::UtcNow
$collectedAt = $now.ToUnixTimeSeconds()
$iso         = $now.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

try {
  $r = Invoke-RestMethod -Uri "http://$TargetHost/health" -TimeoutSec $TimeoutSec
} catch {
  [ordered]@{
    collected_at = $collectedAt
    timestamp    = $iso
    source       = "express-health"
    status       = "error"
    error        = "Health endpoint unreachable or invalid JSON"
    detail       = $_.Exception.Message
    host         = $TargetHost
  } | ConvertTo-Json -Depth 6
  exit 1
}

$status = switch ($r.status) {
  "healthy"  { "ok" }
  "degraded" { "degraded" }
  default    { "unknown" }
}

# pool_waiting may be absent in the health payload; default to 0.
$waiting = if ($null -ne $r.pool_waiting) { $r.pool_waiting } else { 0 }

[ordered]@{
  collected_at        = $collectedAt
  timestamp           = $iso
  source              = "express-health"
  host                = $TargetHost
  status              = $status
  uptime_seconds      = $r.uptime_seconds
  memory_mb           = $r.memory_mb
  requests_per_minute = $r.requests_per_minute
  db                  = [ordered]@{
    status     = $r.db
    latency_ms = $r.db_latency_ms
    pool       = [ordered]@{
      size    = $r.pool_size
      active  = $r.pool_active
      waiting = $waiting
    }
  }
} | ConvertTo-Json -Depth 8

exit 0
