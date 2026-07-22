# framework/executor.ps1
#
# Windows pair of executor.sh. Runs a SAFE ACTION proposed by the analyzer, with
# safety gates read from the action itself (-Describe). SAFE BY DEFAULT: dry-run.
#
# Usage:
#   .\executor.ps1 -Action <id> [-System sistema-rh] [-Execute] [-Confirm]
#                  [-SkipBackup] [-ActionArgs @('-Size','20')]
#
#   -Action <id>     (required) script in examples/<system>/actions/safe/<id>.ps1
#   -System <name>   default: sistema-rh
#   -Execute         opt-in: run the action for real (default is dry-run)
#   -Confirm         allow actions with requires_approval:true
#   -SkipBackup      allow actions with requires_backup_first:true (backup assumed done)
#   -ActionArgs      array forwarded to the action (e.g. @('-Size','20','-Old','10'))
#
# The analyzer PROPOSES; a human picks the action and runs this. Human in the loop.
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $Action,
  [string]   $System     = "sistema-rh",
  [switch]   $Execute,
  [switch]   $Confirm,
  [switch]   $SkipBackup,
  [string[]] $ActionArgs = @()
)

$ErrorActionPreference = "Stop"
$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$script = Join-Path $RepoDir "examples\$System\actions\safe\$Action.ps1"
if (-not (Test-Path -LiteralPath $script)) {
  [Console]::Error.WriteLine("ERROR: action not found: $script"); exit 1
}

try { $desc = (& $script -Describe | Out-String | ConvertFrom-Json) }
catch { [Console]::Error.WriteLine("ERROR: action -Describe did not return JSON."); exit 1 }

$auditLog = if ($env:AIOPS_LOG) { $env:AIOPS_LOG } else { "aiops.log" }
$nowIso   = [DateTimeOffset]::UtcNow.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
function Write-Audit([string] $result, [int] $rc) {
  $line = ([ordered]@{ at = $nowIso; action = $Action; mode = "execute"; result = $result; rc = $rc } | ConvertTo-Json -Compress)
  Add-Content -LiteralPath $auditLog -Value $line -Encoding UTF8
}

# ============================ DRY-RUN (default) ============================
if (-not $Execute) {
  [Console]::Error.WriteLine("=== DRY-RUN - nothing was executed ===")
  Write-Output ("Action:               " + $Action)
  Write-Output ("Reversible:           " + $desc.reversible)
  Write-Output ("Requires approval:    " + $desc.requires_approval + "   (-Confirm)")
  Write-Output ("Requires backup:      " + $desc.requires_backup_first + "   (-SkipBackup)")
  Write-Output ("Requires Win admin:   " + $desc.windows_admin_required)
  Write-Output ("Command that would run: " + $desc.command)
  Write-Output ("Rollback:             " + $desc.rollback)
  if ($desc.prerequisite) { Write-Output ("PREREQUISITE:         " + $desc.prerequisite) }
  [Console]::Error.WriteLine("To run: re-run with -Execute (plus -Confirm/-SkipBackup if required).")
  exit 0
}

# ============================ EXECUTE (opt-in) ============================
if ($desc.requires_approval -eq $true -and -not $Confirm) {
  [Console]::Error.WriteLine("REFUSED: action requires approval. Re-run with -Confirm."); exit 3
}
if ($desc.requires_backup_first -eq $true -and -not $SkipBackup) {
  [Console]::Error.WriteLine("REFUSED: action requires a backup first. Back up, then use -SkipBackup."); exit 3
}
if ($desc.windows_admin_required -eq $true) {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    [Console]::Error.WriteLine("REFUSED: action needs an elevated (Administrator) PowerShell."); exit 3
  }
}

[Console]::Error.WriteLine("Executing: $Action ...")
& $script -Run @ActionArgs
$rc = $LASTEXITCODE
if ($rc -eq 0) {
  Write-Audit "success" 0
  [Console]::Error.WriteLine("OK: $Action done.")
} else {
  [Console]::Error.WriteLine("FAILED (rc=$rc). Attempting rollback...")
  & $script -Rollback @ActionArgs
  if ($LASTEXITCODE -eq 0) {
    Write-Audit "rolled-back" $rc
    [Console]::Error.WriteLine("Rollback OK.")
  } else {
    Write-Audit "rollback-failed" $rc
    [Console]::Error.WriteLine("ROLLBACK FAILED - manual intervention required.")
    exit 1
  }
}
