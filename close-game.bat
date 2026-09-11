@echo off
chcp 65001 >nul
taskkill /F /IM Unitates.exe >nul 2>nul
echo Игра закрыта. Теперь можно собирать билд в Unity.
pause
