@echo off
title Cathedral School Schedule Display - Installer
color 0B

echo.
echo   Christ Church Cathedral School
echo   Schedule Display - Installer
echo   ------------------------------------------------
echo.

REM Windows will not let us change system settings without permission, so
REM re-launch this same file elevated if we are not already.
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo   Asking Windows for permission...
    echo   Please click YES on the prompt that appears.
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\windows\Install-Display.ps1" -SourceRoot "%~dp0app"

if %errorlevel% neq 0 (
    echo.
    echo   SOMETHING WENT WRONG. The message above says what.
    echo   Send a photo of this window to cccs@henryjess.ca
    echo.
)

echo   You can close this window and unplug the USB stick.
echo.
pause
