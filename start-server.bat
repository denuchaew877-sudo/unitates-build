@echo off
chcp 65001 >nul
title DEEPER Server
cd /d "%~dp0"
if not exist "%~dp0Unitates.exe" (
  echo Unitates.exe not found in this folder.
  echo.
  pause
  exit /b 1
)
echo.
echo Drug iz DRUGOGO GORODA. Ne day emu 192.168 i ne 127.0.0.1
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open-wan.ps1"
echo.
echo Start server. Close this window to stop.
echo.
"%~dp0Unitates.exe" -batchmode -nographics -deeper-server -logfile -
