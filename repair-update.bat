@echo off
chcp 65001 >nul
title UNITATES — починить обновление
cd /d "%~dp0"
echo Удаляю update-config.local.txt (из-за него у игрока не качается патч)
del /f /q "%~dp0update-config.local.txt" 2>nul
echo Качаю свежий update-and-play.ps1 с GitHub
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/denuchaew877-sudo/unitates-build/main/update-and-play.ps1' -OutFile '%~dp0update-and-play.ps1'"
if errorlevel 1 (
  echo Не скачалось. Проверь интернет.
  pause
  exit /b 1
)
echo Запускаю обновление
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-and-play.ps1"
if errorlevel 1 pause
