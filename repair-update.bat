@echo off
chcp 65001 >nul
title UNITATES — починить обновление
cd /d "%~dp0"
echo Закрой старое чёрное окно, если оно ещё висит.
echo Удаляю update-config.local.txt
del /f /q "%~dp0update-config.local.txt" 2>nul
echo Качаю лаунчер с зеркала (не raw.githubusercontent.com)
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri 'https://cdn.jsdelivr.net/gh/denuchaew877-sudo/unitates-build@main/update-and-play.ps1' -OutFile '%~dp0update-and-play.ps1'"
if errorlevel 1 (
  echo Зеркало не ответило. Проверь интернет.
  pause
  exit /b 1
)
echo Запускаю игру. Если версия уже новая — просто откроется.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-and-play.ps1"
if errorlevel 1 pause
