<#
.SYNOPSIS
    Undoes Install-Display.ps1 and puts the PC back to normal.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\CathedralScheduleDisplay',
    [switch]$KeepTouchDisabled,
    [switch]$KeepFiles
)

$ErrorActionPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator. Double-click UNINSTALL.bat instead.'
}

foreach ($task in 'CathedralScheduleDisplay', 'CathedralScheduleDisplayWatchdog', 'CathedralScheduleDisplayNightlyReboot') {
    Write-Host "Removing scheduled task $task"
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host 'Stopping the display'
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
    Where-Object { $_.CommandLine -like "*$InstallRoot*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$profileDir = Join-Path $env:LOCALAPPDATA 'CathedralScheduleKiosk'
Get-CimInstance Win32_Process -Filter "Name = 'msedge.exe' OR Name = 'chrome.exe'" |
    Where-Object { $_.CommandLine -like "*$profileDir*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host 'Restoring power settings'
powercfg /change monitor-timeout-ac 15
powercfg /change standby-timeout-ac 30

Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' `
    -Name 'ToastEnabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue

if (-not $KeepTouchDisabled) {
    $enable = Join-Path $InstallRoot 'windows\Enable-Touchscreen.ps1'
    if (Test-Path $enable) { & $enable } else { Write-Warning 'Enable-Touchscreen.ps1 not found; re-enable touch from Device Manager.' }
}

# The installed files are left in place by default: they hold the .env and any
# theme edits made on this PC, which are worth keeping.
if ($KeepFiles) {
    Write-Host "Files left at $InstallRoot"
} elseif (Test-Path $InstallRoot) {
    Write-Host "Files left at $InstallRoot (delete the folder by hand if you want them gone)."
}

Write-Host ''
Write-Host 'Display removed.' -ForegroundColor Green
