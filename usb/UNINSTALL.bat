@echo off
title Cathedral School Schedule Display - Uninstaller
color 0E

echo.
echo   Removing the schedule display from this PC.
echo   The touchscreen will be switched back on.
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo   Asking Windows for permission...
    echo   Please click YES on the prompt that appears.
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\windows\Uninstall-Display.ps1"

echo.
pause
