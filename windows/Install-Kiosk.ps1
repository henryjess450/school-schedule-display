<#
.SYNOPSIS
    One-time setup of this PC as a schedule display kiosk.
.DESCRIPTION
    Registers the logon and watchdog scheduled tasks, stops the machine sleeping
    or blanking, quiets notification toasts, and (unless -KeepTouch) disables the
    touchscreen. Everything it changes is undone by Uninstall-Kiosk.ps1.

    Run once, elevated, signed in as the account the display will run under.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-Kiosk.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-Kiosk.ps1 -Browser Chrome -KeepTouch
#>
[CmdletBinding()]
param(
    [string]$Url = 'http://localhost:8080',
    [ValidateSet('Edge', 'Chrome')]
    [string]$Browser = 'Edge',
    [switch]$KeepTouch
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

$user = "$env:USERDOMAIN\$env:USERNAME"
$startScript = Join-Path $PSScriptRoot 'Start-Kiosk.ps1'
$watchdogScript = Join-Path $PSScriptRoot 'Watchdog-Kiosk.ps1'

# --- Power and screen ------------------------------------------------------
Write-Host 'Preventing sleep and screen blanking...'
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change disk-timeout-ac 0

Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveActive' -Value '0'
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveTimeOut' -Value '0'

# --- Notifications ---------------------------------------------------------
Write-Host 'Suppressing notification toasts...'
$pushKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
New-Item -Path $pushKey -Force | Out-Null
Set-ItemProperty -Path $pushKey -Name 'ToastEnabled' -Value 0 -Type DWord

# --- Touchscreen -----------------------------------------------------------
if ($KeepTouch) {
    Write-Host 'Leaving touch input enabled (-KeepTouch).'
} else {
    Write-Host 'Disabling the touchscreen...'
    & (Join-Path $PSScriptRoot 'Disable-Touchscreen.ps1')
}

# --- Scheduled tasks -------------------------------------------------------
Write-Host 'Registering scheduled tasks...'

$commonSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# Launch at logon. A short delay lets Docker Desktop get going first.
$startAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`" -Url $Url -Browser $Browser"
$startTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$startTrigger.Delay = 'PT30S'

Register-ScheduledTask -TaskName 'SchoolScheduleKiosk' `
    -Action $startAction -Trigger $startTrigger -Settings $commonSettings `
    -RunLevel Limited -User $user -Force | Out-Null

# Watchdog every 5 minutes.
$watchdogAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchdogScript`" -Url $Url -Browser $Browser"
$watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName 'SchoolScheduleKioskWatchdog' `
    -Action $watchdogAction -Trigger $watchdogTrigger -Settings $commonSettings `
    -RunLevel Limited -User $user -Force | Out-Null

# Nightly reboot keeps Windows Update and any browser leak from ever surfacing
# during school hours.
$rebootAction = New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '/r /t 60 /f'
$rebootTrigger = New-ScheduledTaskTrigger -Daily -At '03:30'
Register-ScheduledTask -TaskName 'SchoolScheduleKioskNightlyReboot' `
    -Action $rebootAction -Trigger $rebootTrigger -Settings $commonSettings `
    -RunLevel Highest -User 'SYSTEM' -Force | Out-Null

Write-Host ''
Write-Host 'Kiosk installed.' -ForegroundColor Green
Write-Host "  Display URL : $Url"
Write-Host "  Browser     : $Browser"
Write-Host "  Runs as     : $user at logon"
Write-Host ''
Write-Host 'Remaining manual steps:'
Write-Host '  1. Set Docker Desktop to "Start Docker Desktop when you log in".'
Write-Host '  2. Set this account to sign in automatically (netplwiz), or the display stays at the lock screen after a reboot.'
Write-Host '  3. For full lockdown, follow the Assigned Access section in the README.'
Write-Host ''
Write-Host 'Start it now with: schtasks /run /tn SchoolScheduleKiosk'
