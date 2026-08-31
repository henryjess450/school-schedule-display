<#
.SYNOPSIS
    Re-enables the touchscreen device(s) that Disable-Touchscreen.ps1 turned off.
.DESCRIPTION
    Reads touchscreen-state.json and re-enables exactly those devices. Use this
    before servicing the PC, or if the display is ever repurposed. Run elevated.
#>
[CmdletBinding()]
param(
    [string]$StatePath = (Join-Path $PSScriptRoot 'touchscreen-state.json')
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

if (-not (Test-Path $StatePath)) {
    throw "No state file at $StatePath. Re-enable the device from Device Manager instead."
}

$devices = Get-Content $StatePath -Raw | ConvertFrom-Json
foreach ($device in @($devices)) {
    Write-Host "Enabling: $($device.FriendlyName)"
    Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
}

Remove-Item $StatePath
Write-Host 'Touch input restored.'
