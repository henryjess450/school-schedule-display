<#
.SYNOPSIS
    Disables the touchscreen digitizer(s) on this PC.
.DESCRIPTION
    The display is information-only, so the panel's touch input is turned off at
    the device level. The instance IDs of everything disabled are recorded in
    touchscreen-state.json so Enable-Touchscreen.ps1 can put things back exactly
    as they were. Run from an elevated PowerShell prompt.
#>
[CmdletBinding()]
param(
    [string]$StatePath
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty inside a param() default on Windows PowerShell 5.1 when
# the script is launched with -File, so resolve the folder here in the body.
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $StatePath) { $StatePath = Join-Path $scriptDir 'touchscreen-state.json' }

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

# Touch digitizers report as HID devices whose name mentions a touch screen.
# Pen/stylus digitizers are deliberately left alone.
$touchDevices = Get-PnpDevice -Class 'HIDClass' -Status 'OK' |
    Where-Object { $_.FriendlyName -match '(?i)touch\s*screen|touchscreen|touch device' }

if (-not $touchDevices) {
    Write-Warning 'No touchscreen devices found. Nothing to disable.'
    Write-Warning 'Run "Get-PnpDevice -Class HIDClass | Format-Table FriendlyName, InstanceId" to inspect what this PC reports.'
    return
}

$disabled = @()
foreach ($device in $touchDevices) {
    Write-Host "Disabling: $($device.FriendlyName)"
    Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
    $disabled += [pscustomobject]@{
        InstanceId   = $device.InstanceId
        FriendlyName = $device.FriendlyName
    }
}

$disabled | ConvertTo-Json -Depth 3 | Set-Content -Path $StatePath -Encoding UTF8
Write-Host "Disabled $($disabled.Count) device(s). State written to $StatePath"
