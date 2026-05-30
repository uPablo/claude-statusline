# Installer for claude-statusline (Windows / PowerShell)
$ErrorActionPreference = 'Stop'

$src  = Join-Path $PSScriptRoot 'status-line.ps1'
$dir  = Join-Path $env:USERPROFILE '.claude\scripts'
$dest = Join-Path $dir 'status-line.ps1'

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item $src $dest -Force
Write-Host "✓ Installed to $dest"
Write-Host ""
Write-Host "Add this to %USERPROFILE%\.claude\settings.json, then restart Claude Code:"
Write-Host ""
@'
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File \"%USERPROFILE%\\.claude\\scripts\\status-line.ps1\"",
    "refreshInterval": 10
  }
'@ | Write-Host
Write-Host ""
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
  Write-Host "ℹ pwsh (PowerShell 7+) not found. Either install it (winget install Microsoft.PowerShell)"
  Write-Host "  or change the command to: powershell -NoProfile -File ..."
}
if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
  Write-Host "ℹ jq not required for the PowerShell version (uses ConvertFrom-Json)."
}
if (-not (Get-Command ccusage -ErrorAction SilentlyContinue)) {
  Write-Host "ℹ ccusage not found — optional (burn rate + daily cost). Install with: npm i -g ccusage"
}
