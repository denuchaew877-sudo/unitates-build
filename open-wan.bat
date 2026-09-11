@echo off
chcp 65001 >nul
title UNITATES — открыть интернет другу
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open-wan.ps1"
pause
