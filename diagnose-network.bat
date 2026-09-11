@echo off
chcp 65001 >nul
title UNITATES — диагностика сети
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose-network.ps1"
if errorlevel 1 pause
