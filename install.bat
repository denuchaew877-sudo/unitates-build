@echo off
chcp 65001 >nul
title UNITATES — установка
set "URL=%~1"
if "%URL%"=="" (
  echo Вставь адрес Git-репозитория с билдом.
  echo Пример: https://github.com/denuchaew877-sudo/unitates-build.git
  if "%URL%"=="" set "URL=https://github.com/denuchaew877-sudo/unitates-build.git"
)
if "%URL%"=="" (
  echo Адрес пустой.
  pause
  exit /b 1
)
where git >nul 2>nul
if errorlevel 1 (
  echo Нужен Git: https://git-scm.com/download/win
  pause
  exit /b 1
)
set "DEST=%~dp0UnitatesGame"
if not "%~2"=="" set "DEST=%~2"
echo Клонирую в "%DEST%"
git clone --branch main "%URL%" "%DEST%"
if errorlevel 1 (
  echo Не удалось клонировать.
  pause
  exit /b 1
)
copy /Y "%~dp0play.bat" "%DEST%\play.bat" >nul
copy /Y "%~dp0update-and-play.ps1" "%DEST%\update-and-play.ps1" >nul
echo.
echo Готово. Запускаю.
cd /d "%DEST%"
call play.bat
