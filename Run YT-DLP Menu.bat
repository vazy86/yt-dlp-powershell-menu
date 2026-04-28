@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0yt-dlp-menu.ps1"
if errorlevel 1 (
    echo.
    echo Script exited with an error.
    pause
)
