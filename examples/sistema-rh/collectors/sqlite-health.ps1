# examples/sistema-rh/collectors/sqlite-health.ps1
#
# Windows pair of sqlite-health.sh. Checks banco.sqlite: integrity, journal mode,
# file size, trivial-query latency, and last backup age.
#
# Usage: .\sqlite-health.ps1 [-Db banco.sqlite] [-BackupDir backups]
#
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [string] $Db        = "banco.sqlite",
  [string] $BackupDir = "backups"
)

$now         = [DateTimeOffset]::UtcNow
$collectedAt = $now.ToUnixTimeSeconds()
$iso         = $now.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

function Write-CollectorError([string] $message) {
  [ordered]@{
    collected_at = $collectedAt
    timestamp    = $iso
    source       = "sqlite-health"
    status       = "error"
    error        = $message
    db           = $Db
  } | ConvertTo-Json -Depth 5
  exit 1
}

if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
  Write-CollectorError "sqlite3 not found (install the SQLite CLI)"
}
if (-not (Test-Path -LiteralPath $Db)) { Write-CollectorError "database not found: $Db" }

$integrity = "unknown"
$journal   = "unknown"
try { $integrity = (& sqlite3 $Db "PRAGMA integrity_check;" | Select-Object -First 1) } catch { }
try { $journal   = (& sqlite3 $Db "PRAGMA journal_mode;"    | Select-Object -First 1) } catch { }

$sizeMb = [int]((Get-Item -LiteralPath $Db).Length / 1MB)

# Trivial-query latency
$latencyMs = $null
try {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & sqlite3 $Db "SELECT 1;" *> $null
  $sw.Stop()
  $latencyMs = [int]$sw.ElapsedMilliseconds
} catch { }

# Last backup
$lastBackupAt   = $null
$lastBackupAgeH = $null
if (Test-Path -LiteralPath $BackupDir) {
  $newest = Get-ChildItem -LiteralPath $BackupDir -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($newest) {
    $lastBackupAt   = $newest.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $lastBackupAgeH = [int]((New-TimeSpan -Start $newest.LastWriteTimeUtc -End $now.UtcDateTime).TotalHours)
  }
}

[ordered]@{
  collected_at          = $collectedAt
  timestamp             = $iso
  source                = "sqlite-health"
  integrity_check       = $integrity
  journal_mode          = $journal
  file_size_mb          = $sizeMb
  latency_ms            = $latencyMs
  last_backup_at        = $lastBackupAt
  last_backup_age_hours = $lastBackupAgeH
} | ConvertTo-Json -Depth 5

exit 0
