# examples/sistema-rh/collectors/tailscale-status.ps1
#
# Windows pair of tailscale-status.sh. VPN state, ping latency and DNS resolution
# for the company server.
#
# Usage: .\tailscale-status.ps1 [-Peer <hostname-or-ip>]
#
# ASCII-only on purpose (PS 5.1 / BOM - see analyzer.ps1 header).

[CmdletBinding()]
param(
  [string] $Peer = ""
)

$now         = [DateTimeOffset]::UtcNow
$collectedAt = $now.ToUnixTimeSeconds()
$iso         = $now.UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")

# --- Tailscale state ---
$tailscale = "unknown"
$tsCmd = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $tsCmd) {
  $tailscale = "not_installed"
} else {
  try {
    $out = & tailscale status 2>&1 | Out-String
    if ($out -match "(?i)logged out|stopped") { $tailscale = "offline" }
    elseif ($LASTEXITCODE -ne 0)              { $tailscale = "offline" }
    else                                      { $tailscale = "connected" }
  } catch { $tailscale = "offline" }
}

# --- Ping and DNS (only when a peer is given) ---
$pingMs      = $null
$pingResult  = $null
$dns         = $null

if ($Peer) {
  try {
    $reply = Test-Connection -ComputerName $Peer -Count 1 -ErrorAction Stop
    # PS 5.1 returns Win32_PingStatus with ResponseTime
    $pingMs     = [int]$reply.ResponseTime
    $pingResult = "ok"
  } catch {
    $pingResult = "no response"
  }

  try {
    $null = Resolve-DnsName -Name $Peer -ErrorAction Stop
    $dns = "ok"
  } catch {
    $dns = "SERVFAIL"
  }
}

[ordered]@{
  collected_at = $collectedAt
  timestamp    = $iso
  source       = "tailscale-status"
  tailscale    = $tailscale
  peer         = $(if ($Peer) { $Peer } else { $null })
  ping_ms      = $pingMs
  ping_result  = $pingResult
  dns          = $dns
} | ConvertTo-Json -Depth 5

exit 0
