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
echo DEEPER dedicated server
echo Close this window to stop the server.
echo Friends on the same LAN will see it under Servers.
echo.
"%~dp0Unitates.exe" -batchmode -nographics -deeper-server -logfile -
