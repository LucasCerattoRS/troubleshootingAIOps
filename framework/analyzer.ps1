# framework/analyzer.ps1
#
# Analyzer do AIOps (PowerShell) - par do analyzer.sh.
# Takes an incident (correlator JSON), builds the specialized prompt, and - if
# authorized - calls Claude to diagnose and propose actions.
#
# SAFE BY DEFAULT: runs in -DryRun (builds and prints the prompt, does NOT call
# the API). Only touches the network with -Execute.
#
# Comments/strings are intentionally ASCII: Windows PowerShell 5.1 reads a
# UTF-8-without-BOM script as ANSI and would mangle accents. The prompt text
# itself is read from the .md files as UTF-8 at runtime, so Portuguese content
# is preserved on the wire.
#
# Usage:
#   .\analyzer.ps1 -IncidentFile <path> [options]
#
# Options:
#   -IncidentFile <path>          (required) incident JSON
#   -System <name>                default: sistema-rh
#   -ConfidenceThreshold <n>      default: 0.70
#   -Model <id>                   default: claude-opus-4-8
#   -Output <path>                save output instead of stdout
#   -DryRun                       (DEFAULT) print prompt + request; no API call
#   -Execute                      opt-in: call the API (needs ANTHROPIC_API_KEY)

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $IncidentFile,
  [string] $System = "sistema-rh",
  [string] $ConfidenceThreshold = "0.70",
  [string] $Model = "claude-opus-4-8",
  [string] $Output = "",
  [switch] $DryRun,
  [switch] $Execute
)

$ErrorActionPreference = "Stop"
$MaxTokens = 8000

# --- Resolve paths relative to this script ---
$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# --- Validations ---
if (-not (Test-Path -LiteralPath $IncidentFile)) {
  [Console]::Error.WriteLine("ERROR: incident not found: $IncidentFile"); exit 1
}
try { Get-Content -Raw -Encoding UTF8 $IncidentFile | ConvertFrom-Json | Out-Null }
catch { [Console]::Error.WriteLine("ERROR: incident is not valid JSON."); exit 1 }

$Template    = Join-Path $RepoDir "framework\analyzer-template.prompt"
$Specialized = Join-Path $RepoDir "examples\$System\analyzer.md"
if (-not (Test-Path -LiteralPath $Template))    { [Console]::Error.WriteLine("ERROR: template not found: $Template"); exit 1 }
if (-not (Test-Path -LiteralPath $Specialized)) { [Console]::Error.WriteLine("ERROR: specialized prompt not found: $Specialized"); exit 1 }

# --- Build the prompt (read .md files as UTF-8 to keep Portuguese intact) ---
$templateText    = Get-Content -Raw -Encoding UTF8 $Template
$specializedText = Get-Content -Raw -Encoding UTF8 $Specialized
$incidentCompact = (Get-Content -Raw -Encoding UTF8 $IncidentFile | ConvertFrom-Json | ConvertTo-Json -Depth 30 -Compress)

$promptText = @"
$templateText

$specializedText

## Analysis parameters
- confidence_threshold: $ConfidenceThreshold  (if diagnosis confidence is below this, return actions: [] and ask for more data)

## Incidente

$incidentCompact
"@

# --- Build the request body (Messages API) ---
$body = [ordered]@{
  model         = $Model
  max_tokens    = $MaxTokens
  thinking      = @{ type = "adaptive" }
  output_config = @{ effort = "high" }
  messages      = @(@{ role = "user"; content = $promptText })
}
$bodyJson = $body | ConvertTo-Json -Depth 8

# ============================ DRY-RUN (default) ============================
# Default to dry-run unless -Execute was passed.
if (-not $Execute) {
  [Console]::Error.WriteLine("=== DRY-RUN - nothing was sent to the API ===")
  [Console]::Error.WriteLine("--- BUILT PROMPT ---")
  Write-Output $promptText
  [Console]::Error.WriteLine("--- REQUEST BODY (would go to POST /v1/messages) ---")
  Write-Output $bodyJson
  [Console]::Error.WriteLine("=== To run for real: re-run with -Execute (needs ANTHROPIC_API_KEY) ===")
  exit 0
}

# ============================ EXECUTE (opt-in) ============================
if (-not $env:ANTHROPIC_API_KEY) {
  [Console]::Error.WriteLine("ERROR: -Execute needs ANTHROPIC_API_KEY in the environment (Lukas rotates accounts via /login).")
  exit 1
}

$headers = @{
  "x-api-key"         = $env:ANTHROPIC_API_KEY
  "anthropic-version" = "2023-06-01"
}
# Send the body as UTF-8 bytes so accents survive PS 5.1's default encoding.
$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

try {
  $resp = Invoke-RestMethod -Method Post -Uri "https://api.anthropic.com/v1/messages" `
    -Headers $headers -ContentType "application/json; charset=utf-8" -Body $bodyBytes
} catch {
  [Console]::Error.WriteLine("ERROR calling the API: $($_.Exception.Message)")
  exit 1
}

if ($resp.type -eq "error") {
  [Console]::Error.WriteLine("API ERROR: $($resp.error | ConvertTo-Json -Depth 6)")
  exit 1
}

# Extract the text block (skip thinking blocks) and validate as JSON.
$diagnosis = ($resp.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join "`n"
try { $diagnosis | ConvertFrom-Json | Out-Null }
catch {
  [Console]::Error.WriteLine("WARNING: model output is not pure JSON. Raw below:")
  Write-Output $diagnosis
  exit 2
}

if ($Output) {
  # UTF-8 without BOM so downstream jq/readers are happy.
  [System.IO.File]::WriteAllText($Output, $diagnosis, (New-Object System.Text.UTF8Encoding($false)))
  [Console]::Error.WriteLine("Diagnosis saved to: $Output")
} else {
  Write-Output $diagnosis
}
