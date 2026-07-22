# examples/sistema-rh/actions/safe/clear-cache.ps1
#
# SAFE (reversible) action: invalidate the app cache. The cache rebuilds on
# demand, so "rollback" is a no-op.
# Modes: -Describe | -Run | -Rollback
#
# PREREQUISITE: depends on POST /api/admin/cache/clear, which does NOT exist in
# Sistema RH today (see actions/README.md).
#
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [switch] $Describe,
  [switch] $Run,
  [switch] $Rollback,
  [string] $TargetHost = "localhost:3000"
)

if ($Describe) {
  @'
{
  "id": "clear-cache",
  "reversible": true,
  "requires_approval": false,
  "requires_backup_first": false,
  "windows_admin_required": false,
  "command": "POST /api/admin/cache/clear",
  "rollback": "no-op (cache rebuilds on demand)",
  "prerequisite": "endpoint /api/admin/cache/clear ainda NAO existe no Sistema RH (ver actions/README.md)"
}
'@
  exit 0
}

if ($Run) {
  if (-not $env:RH_TOKEN) { [Console]::Error.WriteLine("ERROR: RH_TOKEN required."); exit 1 }
  $headers = @{ "Authorization" = "Bearer $($env:RH_TOKEN)" }
  Invoke-RestMethod -Method Post -Uri "http://$TargetHost/api/admin/cache/clear" -Headers $headers | Out-Null
  Write-Output "cache invalidated"
  exit 0
}

if ($Rollback) {
  Write-Output "rollback no-op (cache rebuilds on demand)"
  exit 0
}

[Console]::Error.WriteLine("ERROR: use -Describe | -Run | -Rollback")
exit 1
