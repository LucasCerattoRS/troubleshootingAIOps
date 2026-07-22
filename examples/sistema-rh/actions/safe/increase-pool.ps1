# examples/sistema-rh/actions/safe/increase-pool.ps1
#
# SAFE (reversible) action: increase the Sistema RH connection pool.
# Modes: -Describe (metadata for the executor) | -Run | -Rollback
#   -Run:      set pool to -Size (default 20)
#   -Rollback: revert pool to -Old (default 10)
#
# PREREQUISITE: depends on POST /api/admin/pool-size, which does NOT exist in
# Sistema RH today (see actions/README.md). -Run only works once it is added.
# -Describe and the executor dry-run work without it.
#
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [switch] $Describe,
  [switch] $Run,
  [switch] $Rollback,
  [int]    $Size = 20,
  [int]    $Old  = 10,
  [string] $TargetHost = "localhost:3000"
)

if ($Describe) {
  @'
{
  "id": "increase-pool",
  "reversible": true,
  "requires_approval": false,
  "requires_backup_first": false,
  "windows_admin_required": false,
  "command": "POST /api/admin/pool-size {size: N}",
  "rollback": "POST /api/admin/pool-size {size: OLD}",
  "prerequisite": "endpoint /api/admin/pool-size ainda NAO existe no Sistema RH (ver actions/README.md)"
}
'@
  exit 0
}

if ($Run) {
  if (-not $env:RH_TOKEN) { [Console]::Error.WriteLine("ERROR: RH_TOKEN required for the admin call."); exit 1 }
  $headers = @{ "Authorization" = "Bearer $($env:RH_TOKEN)" }
  $body = "{`"size`": $Size}"
  Invoke-RestMethod -Method Post -Uri "http://$TargetHost/api/admin/pool-size" -Headers $headers -ContentType "application/json" -Body $body | Out-Null
  $health = Invoke-RestMethod -Uri "http://$TargetHost/health"
  if ([int]$health.pool_size -ne $Size) { [Console]::Error.WriteLine("ERROR: pool is still $($health.pool_size) (expected $Size)."); exit 1 }
  Write-Output "pool -> $Size"
  exit 0
}

if ($Rollback) {
  if (-not $env:RH_TOKEN) { [Console]::Error.WriteLine("ERROR: RH_TOKEN required."); exit 1 }
  $headers = @{ "Authorization" = "Bearer $($env:RH_TOKEN)" }
  $body = "{`"size`": $Old}"
  Invoke-RestMethod -Method Post -Uri "http://$TargetHost/api/admin/pool-size" -Headers $headers -ContentType "application/json" -Body $body | Out-Null
  Write-Output "pool reverted -> $Old"
  exit 0
}

[Console]::Error.WriteLine("ERROR: use -Describe | -Run | -Rollback")
exit 1
