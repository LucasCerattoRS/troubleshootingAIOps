# framework/correlator.ps1
#
# Windows pair of correlator.sh. Joins collector outputs into one incident JSON
# that the analyzer consumes. Driven by a manifest.
#
# Usage:
#   .\correlator.ps1 -Manifest <path> [-MockDir <dir>] [-Output <path>]
#
#   -Manifest <path>   (required) maps signals -> collectors
#   -MockDir <dir>     read pre-recorded collector outputs (offline, no network)
#   -Output <path>     save the incident (default: stdout)
#
# A failing collector does NOT abort the rest - the slot gets an error JSON.
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $Manifest,
  [string] $MockDir = "",
  [string] $Output  = ""
)

$ErrorActionPreference = "Stop"
$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

if (-not (Test-Path -LiteralPath $Manifest)) {
  [Console]::Error.WriteLine("ERROR: manifest not found: $Manifest"); exit 1
}
try { $mf = Get-Content -Raw -Encoding UTF8 $Manifest | ConvertFrom-Json }
catch { [Console]::Error.WriteLine("ERROR: manifest is not valid JSON."); exit 1 }

# --- Window and incident id ---
$windowMin = if ($mf.window_minutes) { [int]$mf.window_minutes } else { 3 }
$now       = [DateTimeOffset]::UtcNow
$iso       = $now.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
$winStart  = $now.UtcDateTime.AddMinutes(-$windowMin).ToString("yyyy-MM-ddTHH:mm:ssZ")
$rand      = -join ((1..3) | ForEach-Object { '{0:X}' -f (Get-Random -Maximum 16) })
$incidentId = "INC-" + $now.UtcDateTime.ToString("yyyy-MM-dd") + "-" + $rand

function New-ErrorSignal([string] $slot, [string] $detail) {
  [ordered]@{ source = $slot; status = "error"; error = $detail }
}

# --- One slot at a time ---
$signals = [ordered]@{}
foreach ($prop in $mf.signals.PSObject.Properties) {
  $slot = $prop.Name
  $def  = $prop.Value
  $content = $null

  if ($MockDir) {
    $mockPath = Join-Path $MockDir $def.mock
    if ($def.mock -and (Test-Path -LiteralPath $mockPath)) {
      try { $content = Get-Content -Raw -Encoding UTF8 $mockPath | ConvertFrom-Json }
      catch { $content = New-ErrorSignal $slot "mock is not valid JSON: $mockPath" }
    } else {
      $content = New-ErrorSignal $slot "mock not found: $mockPath"
    }
  } else {
    $collectorRel = $def.ps1.collector
    $collector    = Join-Path $RepoDir ($collectorRel -replace '/', '\')
    if (-not $collectorRel -or -not (Test-Path -LiteralPath $collector)) {
      $content = New-ErrorSignal $slot "collector missing: $collectorRel"
    } else {
      try {
        $args = @($def.ps1.args)
        $raw  = & $collector @args | Out-String
        $content = $raw | ConvertFrom-Json
      } catch {
        $content = New-ErrorSignal $slot "collector failed or non-JSON output"
      }
    }
  }

  $signals[$slot] = $content
}

$incident = [ordered]@{
  incident = [ordered]@{
    id        = $incidentId
    timestamp = $iso
    window    = [ordered]@{ start = $winStart; end = $iso }
  }
  symptoms = @()
  signals  = $signals
}

$json = $incident | ConvertTo-Json -Depth 30

if ($Output) {
  [System.IO.File]::WriteAllText($Output, $json, (New-Object System.Text.UTF8Encoding($false)))
  [Console]::Error.WriteLine("Incident saved to: $Output")
} else {
  Write-Output $json
}
