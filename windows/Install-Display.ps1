<#
.SYNOPSIS
    Sets this PC up as the Cathedral School schedule display.
.DESCRIPTION
    Copies the app off the USB stick to a local folder, writes its settings,
    disables the touchscreen, stops the PC sleeping, and registers the tasks that
    start the display at logon and keep it alive.

    Normally launched by double-clicking INSTALL.bat on the USB stick, which
    handles asking for Administrator. Can also be run directly from an elevated
    PowerShell prompt.
.PARAMETER SourceRoot
    Where the app is being installed from. Defaults to the folder above this
    script, which is what the USB layout gives us.
.PARAMETER InstallRoot
    Where to install to. The USB can then be removed.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = '',
    [string]$InstallRoot = 'C:\CathedralScheduleDisplay',
    [string]$Url = 'http://localhost:8080',
    [ValidateSet('Edge', 'Chrome')]
    [string]$Browser = 'Edge',
    [switch]$KeepTouch
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty inside a param() default on Windows PowerShell 5.1 with
# -File, so resolve the source folder here in the body.
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $SourceRoot) { $SourceRoot = Split-Path $scriptDir -Parent }

trap {
    Write-Host ''
    Write-Host '  INSTALL STOPPED at the step above.' -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    Write-Host '  Nothing was left half-configured that matters. You can just' -ForegroundColor Yellow
    Write-Host '  run INSTALL.bat again. If it keeps stopping here, send a photo' -ForegroundColor Yellow
    Write-Host '  of this window to cccs@henryjess.ca' -ForegroundColor Yellow
    Write-Host ''
    if ($Host.Name -eq 'ConsoleHost') { Read-Host 'Press Enter to close' }
    exit 1
}

function Write-Step($message) { Write-Host "`n>> $message" -ForegroundColor Cyan }
function Write-Ok($message)   { Write-Host "   $message" -ForegroundColor Green }
function Write-Note($message) { Write-Host "   $message" -ForegroundColor Yellow }

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator. Double-click INSTALL.bat instead, and click Yes when Windows asks.'
}

Write-Host ''
Write-Host '  Christ Church Cathedral School - Schedule Display' -ForegroundColor White
Write-Host '  ------------------------------------------------' -ForegroundColor DarkGray

# --- 1. Copy the app locally ----------------------------------------------
Write-Step "Installing to $InstallRoot"

# Anything already running would hold a lock on the files we are about to
# replace, so stop the old install first.
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
    Where-Object { $_.CommandLine -like "*$InstallRoot*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

foreach ($item in 'src', 'public', 'config', 'tools', 'windows', 'runtime') {
    $from = Join-Path $SourceRoot $item
    if (Test-Path $from) {
        Copy-Item -Path $from -Destination $InstallRoot -Recurse -Force
    }
}
foreach ($file in 'package.json', 'README.md') {
    $from = Join-Path $SourceRoot $file
    if (Test-Path $from) { Copy-Item -Path $from -Destination $InstallRoot -Force }
}

# Dependencies ship as a single zip. As a loose tree they are 1,553 files and
# 16MB, which crawls off a cheap USB stick; zipped they are one 3MB read.
$modulesZip = Join-Path $SourceRoot 'node_modules.zip'
$modulesTree = Join-Path $SourceRoot 'node_modules'
$modulesTarget = Join-Path $InstallRoot 'node_modules'

if (Test-Path $modulesZip) {
    Write-Ok 'Unpacking dependencies...'
    if (Test-Path $modulesTarget) { Remove-Item $modulesTarget -Recurse -Force }
    Expand-Archive -Path $modulesZip -DestinationPath $InstallRoot -Force
} elseif (Test-Path $modulesTree) {
    Write-Ok 'Copying dependencies...'
    robocopy $modulesTree $modulesTarget /E /NFL /NDL /NJH /NJS /NP | Out-Null
    # robocopy uses exit codes below 8 for success.
    if ($LASTEXITCODE -ge 8) { throw "Copying node_modules failed (robocopy $LASTEXITCODE)." }
} else {
    throw 'No dependencies found on the stick (expected node_modules.zip).'
}

# A truncated copy is worse than an obvious failure: the display would start and
# then die on a missing module. Check the packages the app actually imports.
foreach ($package in 'express', 'node-ical', 'rrule', 'uuid') {
    if (-not (Test-Path (Join-Path $modulesTarget "$package\package.json"))) {
        throw "Dependencies are incomplete - '$package' is missing. Re-copy the USB stick."
    }
}
Write-Ok 'Files copied.'

# --- 2. Settings ----------------------------------------------------------
Write-Step 'Writing settings'
$envPath = Join-Path $InstallRoot '.env'
$envExample = Join-Path $SourceRoot '.env.example'

if (Test-Path $envPath) {
    Write-Ok 'Existing .env kept (delete it to start fresh).'
} elseif (Test-Path $envExample) {
    Copy-Item $envExample $envPath -Force
    Write-Ok 'Settings written from .env.example.'
} else {
    @(
        'ICAL_URL=https://calendar.google.com/calendar/ical/reception%40cathedralschool.ca/public/basic.ics'
        'TZ=America/Vancouver'
        'REFRESH_SECONDS=120'
        'PORT=8080'
    ) | Set-Content -Path $envPath -Encoding UTF8
    Write-Ok 'Default settings written.'
}

# --- 3. Power and screen --------------------------------------------------
Write-Step 'Stopping the PC sleeping or blanking the screen'
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
powercfg /change hibernate-timeout-ac 0
powercfg /change disk-timeout-ac 0
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveActive' -Value '0'
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaveTimeOut' -Value '0'
Write-Ok 'Done.'

# --- 4. Notifications -----------------------------------------------------
Write-Step 'Silencing notification pop-ups'
# Cosmetic only. New-Item -Force on an existing key throws, so create it just
# when it is missing, and never let this step abort the install.
try {
    $pushKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
    if (-not (Test-Path $pushKey)) { New-Item -Path $pushKey -Force | Out-Null }
    Set-ItemProperty -Path $pushKey -Name 'ToastEnabled' -Value 0 -Type DWord
    Write-Ok 'Done.'
} catch {
    Write-Note "Skipped (not essential): $($_.Exception.Message)"
}

# --- 5. Touchscreen -------------------------------------------------------
if ($KeepTouch) {
    Write-Step 'Leaving touch input enabled (-KeepTouch)'
} else {
    Write-Step 'Disabling the touchscreen'
    # An unusual digitizer must not stop the display from installing; touch can
    # always be turned off by hand afterwards.
    try {
        & (Join-Path $InstallRoot 'windows\Disable-Touchscreen.ps1')
    } catch {
        Write-Note "Could not disable touch automatically: $($_.Exception.Message)"
        Write-Note 'Turn it off later in Device Manager if needed.'
    }
}

# --- 6. Scheduled tasks ---------------------------------------------------
Write-Step 'Registering start-up tasks'
$user = "$env:USERDOMAIN\$env:USERNAME"
$startScript = Join-Path $InstallRoot 'windows\Start-Display.ps1'
$watchdogScript = Join-Path $InstallRoot 'windows\Watchdog-Display.ps1'

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

$startAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$startScript`" -Url $Url -Browser $Browser"
$startTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$startTrigger.Delay = 'PT15S'
Register-ScheduledTask -TaskName 'CathedralScheduleDisplay' `
    -Action $startAction -Trigger $startTrigger -Settings $settings `
    -RunLevel Limited -User $user -Force | Out-Null

$watchdogAction = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchdogScript`" -Url $Url -Browser $Browser"
$watchdogTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddMinutes(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName 'CathedralScheduleDisplayWatchdog' `
    -Action $watchdogAction -Trigger $watchdogTrigger -Settings $settings `
    -RunLevel Limited -User $user -Force | Out-Null

# A nightly reboot keeps Windows Update from ever interrupting the school day.
$rebootAction = New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '/r /t 60 /f'
$rebootTrigger = New-ScheduledTaskTrigger -Daily -At '03:30'
Register-ScheduledTask -TaskName 'CathedralScheduleDisplayNightlyReboot' `
    -Action $rebootAction -Trigger $rebootTrigger -Settings $settings `
    -RunLevel Highest -User 'SYSTEM' -Force | Out-Null
Write-Ok 'Tasks registered.'

# --- 7. Start it now ------------------------------------------------------
Write-Step 'Starting the display'
Start-ScheduledTask -TaskName 'CathedralScheduleDisplay'
Write-Ok 'Started.'

Write-Host ''
Write-Host '  Installed.' -ForegroundColor Green
Write-Host "  The display should appear within a few seconds at $Url"
Write-Host ''
Write-Host '  One thing left to do by hand:' -ForegroundColor White
Write-Note 'Set this account to sign in automatically, or a reboot will leave'
Write-Note 'the panel on the lock screen. Run  netplwiz , untick "Users must'
Write-Note 'enter a user name and password", and enter this account''s password.'
Write-Host ''
Write-Host '  To undo everything: run UNINSTALL.bat from the USB stick.' -ForegroundColor DarkGray
Write-Host ''
