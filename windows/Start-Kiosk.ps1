<#
.SYNOPSIS
    Brings up the schedule container and opens it full screen in kiosk mode.
.DESCRIPTION
    This is the script the scheduled task runs at logon. It starts Docker's
    containers, waits for the app to report healthy, then launches Edge (or
    Chrome) locked to the display URL with no chrome, no menus and no
    navigation. Nothing here needs Administrator.
#>
[CmdletBinding()]
param(
    [string]$Url = 'http://localhost:8080',
    [int]$HealthTimeoutSeconds = 180,
    [ValidateSet('Edge', 'Chrome')]
    [string]$Browser = 'Edge'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

function Write-Log($message) {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
}

# --- 1. Docker -------------------------------------------------------------
# Docker Desktop can take a while after a cold boot, so wait for the engine
# rather than failing the whole launch.
Write-Log 'Waiting for the Docker engine...'
$engineDeadline = (Get-Date).AddSeconds(180)
while ((Get-Date) -lt $engineDeadline) {
    docker info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 5
}
if ($LASTEXITCODE -ne 0) { throw 'Docker did not become available. Is Docker Desktop set to start at login?' }

Write-Log 'Starting the schedule container...'
Push-Location $repoRoot
try {
    docker compose up -d --build
    if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }
}
finally {
    Pop-Location
}

# --- 2. Health -------------------------------------------------------------
Write-Log 'Waiting for the display to report healthy...'
$healthUrl = "$Url/healthz"
$deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
$healthy = $false
while ((Get-Date) -lt $deadline) {
    try {
        $response = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 5
        if ($response.ok) { $healthy = $true; break }
    }
    catch {
        Start-Sleep -Seconds 3
    }
}
if (-not $healthy) { Write-Warning 'App never reported healthy; opening the browser anyway so the screen is not blank.' }

# --- 3. Browser ------------------------------------------------------------
$candidates = if ($Browser -eq 'Chrome') {
    @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
} else {
    @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )
}

$exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { throw "Could not find $Browser. Pass -Browser Chrome or install Edge." }

# A dedicated profile keeps the kiosk free of any signed-in account, saved
# passwords or history from normal staff use of the same PC.
$profileDir = Join-Path $env:LOCALAPPDATA 'SchoolScheduleKiosk'
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

$arguments = @(
    "--user-data-dir=`"$profileDir`""
    '--kiosk'
    $Url
    '--no-first-run'
    '--fast'
    '--fast-start'
    '--noerrdialogs'
    '--disable-infobars'
    '--disable-session-crashed-bubble'
    '--disable-pinch'
    '--overscroll-history-navigation=0'
    '--disable-translate'
    '--disable-features=TranslateUI,Translate,EdgeAutofill,msEdgeAutoFill'
    '--check-for-update-interval=31536000'
    '--autoplay-policy=no-user-gesture-required'
)
if ($Browser -eq 'Edge') { $arguments += '--edge-kiosk-type=fullscreen' }

Write-Log "Launching $Browser in kiosk mode at $Url"
Start-Process -FilePath $exe -ArgumentList $arguments
