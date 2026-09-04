<#
.SYNOPSIS
    Restarts the display if the server or the browser has died.
.DESCRIPTION
    Runs every few minutes from a scheduled task. A wall panel gets no human
    attention, so anything that stops has to come back on its own.
#>
[CmdletBinding()]
param(
    [string]$Url = 'http://localhost:8080',
    [ValidateSet('Edge', 'Chrome')]
    [string]$Browser = 'Edge'
)

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$appRoot = Split-Path $scriptDir -Parent
$processName = if ($Browser -eq 'Chrome') { 'chrome' } else { 'msedge' }
$profileDir = Join-Path $env:LOCALAPPDATA 'CathedralScheduleKiosk'

$serverUp = $false
try { $serverUp = (Invoke-RestMethod -Uri "$Url/healthz" -TimeoutSec 5).ok } catch { }

# Only the kiosk's own profile counts, so a member of staff browsing on the same
# PC is never mistaken for a healthy display.
$browserUp = [bool](Get-CimInstance Win32_Process -Filter "Name = '$processName.exe'" |
    Where-Object { $_.CommandLine -like "*$profileDir*" })

if ($serverUp -and $browserUp) { return }

Write-Host "Recovering display (server up: $serverUp, browser up: $browserUp)"
& (Join-Path $scriptDir 'Start-Display.ps1') -Url $Url -Browser $Browser -NoUpdate
