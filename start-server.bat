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
echo Friends: in the game use DIRECT CONNECT (top-right) and this PC IPv4.
echo UDP 7777 game, UDP 7788 discover. Allow inbound in Windows Firewall.
echo.
echo IPv4 on this PC:
for /f "tokens=2 delims=:" %%A in ('ipconfig ^| findstr /c:"IPv4"') do echo   %%A
echo.
"%~dp0Unitates.exe" -batchmode -nographics -deeper-server -logfile -
