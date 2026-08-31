<#
.SYNOPSIS
    Restarts the kiosk browser if it has died.
.DESCRIPTION
    Runs every few minutes from a scheduled task. A wall display gets no human
    attention, so a crashed browser or a stopped container must recover itself.
#>
[CmdletBinding()]
param(
    [string]$Url = 'http://localhost:8080',
    [ValidateSet('Edge', 'Chrome')]
    [string]$Browser = 'Edge'
)

$processName = if ($Browser -eq 'Chrome') { 'chrome' } else { 'msedge' }
$profileDir = Join-Path $env:LOCALAPPDATA 'SchoolScheduleKiosk'

# Only count the kiosk's own profile, so a member of staff browsing on the same
# PC never looks like a healthy kiosk.
$running = Get-CimInstance Win32_Process -Filter "Name = '$processName.exe'" |
    Where-Object { $_.CommandLine -like "*$profileDir*" }

if ($running) { return }

Write-Host "Kiosk browser not running; relaunching."
& (Join-Path $PSScriptRoot 'Start-Kiosk.ps1') -Url $Url -Browser $Browser
