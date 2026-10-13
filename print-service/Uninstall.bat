@echo off
title Parking Manager - Remove Print Service
set "DEST=%LOCALAPPDATA%\ParkingPrintService"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\agent.ps1" -Stop
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Parking Print Service.lnk" 2>nul
echo The print service was stopped and will no longer start at login.
echo Saved receipts are kept in %DEST%\data
pause
