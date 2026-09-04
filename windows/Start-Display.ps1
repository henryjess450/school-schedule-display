<#
.SYNOPSIS
    Starts the schedule server and opens it full screen in kiosk mode.
.DESCRIPTION
    This is what the logon task runs. It starts the Node server using the
    runtime that shipped alongside the app, waits for it to report healthy, then
    launches Edge locked to the display URL with no menus and no navigation.

    Nothing here needs Administrator.
#>
[CmdletBinding()]
param(
    [string]$Url = 'http://localhost:8080',
    [int]$HealthTimeoutSeconds = 90,
    [ValidateSet('Edge', 'Chrome')]
    [string]$Browser = 'Edge',
    [switch]$NoUpdate
)

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$appRoot = Split-Path $scriptDir -Parent

function Write-Log($message) {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
}

# --- 0. Self-update -------------------------------------------------------
# Pull the newest published version before starting, so a reboot (including the
# nightly one) brings the board up to date on its own. Best effort: it only acts
# when GitHub has a newer commit, and any failure leaves the installed files
# alone. The watchdog passes -NoUpdate so a crash-restart doesn't re-check.
if (-not $NoUpdate) {
    try {
        & (Join-Path $scriptDir 'Update-Display.ps1')
    } catch {
        Write-Log "Update check skipped: $($_.Exception.Message)"
    }
}

# --- 1. The server --------------------------------------------------------
# Prefer the runtime that shipped with the app, so the display never depends on
# whatever Node the PC may or may not have.
$bundledNode = Join-Path $appRoot 'runtime\node.exe'
$node = if (Test-Path $bundledNode) { $bundledNode } else { 'node' }

$alreadyRunning = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
    Where-Object { $_.CommandLine -like "*$appRoot*" }

if ($alreadyRunning) {
    Write-Log 'Server already running.'
} else {
    Write-Log "Starting the schedule server with $node"
    $logDir = Join-Path $appRoot 'logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    Start-Process -FilePath $node `
        -ArgumentList 'src\server.js' `
        -WorkingDirectory $appRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logDir 'server.log') `
        -RedirectStandardError (Join-Path $logDir 'server-error.log')
}

# --- 2. Health ------------------------------------------------------------
Write-Log 'Waiting for the display to report healthy...'
$deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
$healthy = $false
while ((Get-Date) -lt $deadline) {
    try {
        if ((Invoke-RestMethod -Uri "$Url/healthz" -TimeoutSec 5).ok) { $healthy = $true; break }
    }
    catch {
        Start-Sleep -Seconds 2
    }
}
if (-not $healthy) {
    Write-Warning 'Server never reported healthy; opening the browser anyway so the screen is not blank.'
}

# --- 3. The browser -------------------------------------------------------
$candidates = if ($Browser -eq 'Chrome') {
    @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")
} else {
    @("$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
      "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")
}

$exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw "Could not find $Browser." }

# A dedicated profile keeps the kiosk clear of any signed-in account, saved
# password or history from normal staff use of the same PC.
$profileDir = Join-Path $env:LOCALAPPDATA 'CathedralScheduleKiosk'
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

$arguments = @(
    "--user-data-dir=`"$profileDir`""
    '--kiosk'
    $Url
    '--no-first-run'
    '--noerrdialogs'
    '--disable-infobars'
    '--disable-session-crashed-bubble'
    '--disable-pinch'
    '--overscroll-history-navigation=0'
    '--disable-translate'
    '--disable-features=TranslateUI,Translate,msEdgeAutoFill'
    '--check-for-update-interval=31536000'
)
if ($Browser -eq 'Edge') { $arguments += '--edge-kiosk-type=fullscreen' }

Write-Log "Launching $Browser in kiosk mode at $Url"
Start-Process -FilePath $exe -ArgumentList $arguments
