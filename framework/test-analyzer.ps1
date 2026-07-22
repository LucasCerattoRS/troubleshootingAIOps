# framework/test-analyzer.ps1
#
# Test runner do analyzer. Windows pair of test-analyzer.sh.
#
#   Offline (padrao, sem credito): valida cada fixture + golden como JSON e roda o
#     analyzer em dry-run, conferindo que o prompt monta.
#   -Execute (gasta credito, opt-in): roda o analyzer de verdade e compara a saida
#     com o golden POR CAMPO (nao diff literal).
#
# Usage: .\test-analyzer.ps1 [-System sistema-rh] [-Execute] [-Threshold 0.15]
#
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [string] $System    = "sistema-rh",
  [switch] $Execute,
  [double] $Threshold = 0.15
)

$ErrorActionPreference = "Stop"
$RepoDir  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$analyzer = Join-Path $RepoDir "framework\analyzer.ps1"
$dir      = Join-Path $RepoDir "examples\$System\test-incidents"

if (-not (Test-Path -LiteralPath $dir)) { [Console]::Error.WriteLine("ERROR: no test-incidents dir: $dir"); exit 1 }

$fixtures = Get-ChildItem -LiteralPath $dir -Filter "case-*.json" |
            Where-Object { $_.Name -notlike "*.expected.json" } | Sort-Object Name

$pass = 0; $fail = 0
$mode = if ($Execute) { "EXECUTE (gasta credito)" } else { "OFFLINE (dry-run, sem credito)" }
Write-Output "== test-analyzer :: $mode :: $($fixtures.Count) casos =="

foreach ($fx in $fixtures) {
  $name   = $fx.BaseName
  $golden = Join-Path $dir ($fx.BaseName + ".expected.json")
  $checks = @()

  # -- JSON valido (fixture + golden) --
  try { Get-Content -Raw -Encoding UTF8 $fx.FullName | ConvertFrom-Json | Out-Null; $checks += "fixture-json" }
  catch { $checks += "FAIL:fixture-json" }
  if (Test-Path -LiteralPath $golden) {
    try { $gold = Get-Content -Raw -Encoding UTF8 $golden | ConvertFrom-Json; $checks += "golden-json" }
    catch { $checks += "FAIL:golden-json"; $gold = $null }
  } else { $checks += "FAIL:golden-missing"; $gold = $null }

  if (-not $Execute) {
    # -- Offline: o analyzer monta o prompt em dry-run? --
    try {
      $dry = & $analyzer -IncidentFile $fx.FullName 2>$null | Out-String
      if ($dry -match "## Incidente" -and $dry -match '"model"') { $checks += "dry-run-builds" }
      else { $checks += "FAIL:dry-run-builds" }
    } catch { $checks += "FAIL:dry-run-error" }
  }
  else {
    # -- Execute: compara saida real com golden por campo --
    try {
      $out = & $analyzer -IncidentFile $fx.FullName -Execute 2>$null | Out-String | ConvertFrom-Json
      if ($out.diagnosis.root_cause) { $checks += "root_cause" } else { $checks += "FAIL:root_cause" }
      if ($gold -and [math]::Abs([double]$out.diagnosis.confidence - [double]$gold.diagnosis.confidence) -le $Threshold) { $checks += "confidence" } else { $checks += "FAIL:confidence" }
      if ($gold -and $out.actions[0].category -eq $gold.actions[0].category) { $checks += "action1-category" } else { $checks += "FAIL:action1-category" }
      if ($out.diagnosis -and $out.impact -and $out.actions) { $checks += "shape" } else { $checks += "FAIL:shape" }
    } catch { $checks += "FAIL:execute-error" }
  }

  $failed = @($checks | Where-Object { $_ -like "FAIL:*" })
  if ($failed.Count -eq 0) { $pass++; Write-Output ("PASS  " + $name + "   [" + ($checks -join ", ") + "]") }
  else                     { $fail++; Write-Output ("FAIL  " + $name + "   [" + ($failed -join ", ") + "]") }
}

Write-Output "== resultado: $pass PASS / $fail FAIL =="
if ($fail -gt 0) { exit 1 } else { exit 0 }
