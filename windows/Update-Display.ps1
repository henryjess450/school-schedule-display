<#
.SYNOPSIS
    Pulls the latest published version of the display from the public repo.
.DESCRIPTION
    Checks the newest commit on GitHub, and only if it differs from what's
    installed does it download and lay down the new files. .env, the bundled
    Node runtime and node_modules are never in the archive, so local settings
    and the runtime are left untouched.

    Best effort: any problem (no network, GitHub down) is swallowed so the
    display always comes up on whatever is already installed. Needs no login —
    the repo is public.
#>
[CmdletBinding()]
param([int]$TimeoutSec = 20)

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$app = Split-Path $scriptDir -Parent

$repo   = 'henryjess450/school-schedule-display'
$branch = 'main'
$versionFile = Join-Path $app '.version'
$headers = @{ 'User-Agent' = 'CathedralScheduleDisplay' }

function Log($m) { Write-Host "[update] $m" }

try {
    # TLS 1.2 for older Windows PowerShell defaults, or GitHub refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $latest = (Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/commits/$branch" -Headers $headers -TimeoutSec $TimeoutSec).sha
    if (-not $latest) { Log 'No version returned; skipping.'; return }

    $current = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { '' }
    if ($latest -eq $current) { Log "Already current ($($latest.Substring(0,7)))."; return }

    Log "New version $($latest.Substring(0,7)) - updating."
    $tmp = Join-Path $env:TEMP ('cccs-update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'main.zip'

    Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/heads/$branch.zip" -OutFile $zip -TimeoutSec $TimeoutSec -Headers $headers
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $extract = Join-Path $tmp "school-schedule-display-$branch"
    if (-not (Test-Path $extract)) { throw 'Unexpected archive layout.' }

    # Overwrite only the version-controlled parts.
    foreach ($item in 'src', 'public', 'config', 'windows', 'tools', 'package.json') {
        $from = Join-Path $extract $item
        if (Test-Path $from) { Copy-Item -Path $from -Destination $app -Recurse -Force }
    }

    Set-Content -Path $versionFile -Value $latest -Encoding ASCII
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Log 'Update applied.'
} catch {
    Log "Skipped ($($_.Exception.Message)) - keeping the installed version."
}
