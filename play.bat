@echo off
chcp 65001 >nul
title UNITATES
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-and-play.ps1"
if errorlevel 1 pause
