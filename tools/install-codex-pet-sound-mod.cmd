@echo off
setlocal
cd /d "%~dp0.."
powershell -ExecutionPolicy Bypass -File "%~dp0install-codex-pet-sound-mod.ps1" %*
echo.
pause
