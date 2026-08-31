<#
.SYNOPSIS
    Undoes Install-Kiosk.ps1: removes the tasks, restores touch and power settings.
#>
[CmdletBinding()]
param([switch]$KeepTouchDisabled)

$ErrorActionPreference = 'Continue'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

foreach ($task in 'SchoolScheduleKiosk', 'SchoolScheduleKioskWatchdog', 'SchoolScheduleKioskNightlyReboot') {
    Write-Host "Removing scheduled task $task"
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
}

Write-Host 'Restoring default power timeouts...'
powercfg /change monitor-timeout-ac 15
powercfg /change standby-timeout-ac 30

Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'ToastEnabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue

if (-not $KeepTouchDisabled) {
    $state = Join-Path $PSScriptRoot 'touchscreen-state.json'
    if (Test-Path $state) { & (Join-Path $PSScriptRoot 'Enable-Touchscreen.ps1') }
}

Write-Host 'Kiosk removed. The container is untouched; stop it with "docker compose down".'
