@echo off
title Parking Manager POS

set "APP_URL=https://time-ticket-printer-src-tauri.vercel.app"
set "PRINTER=HP LaserJet 400 M401 PCL 6"
rem Dedicated browser profile: guarantees --kiosk-printing is applied even if
rem Chrome/Edge is already open, and avoids a remembered "last used" printer.
set "PROFILE_DIR=%LOCALAPPDATA%\ParkingManagerKiosk"

echo Setting default printer to %PRINTER% ...
rundll32 printui.dll,PrintUIEntry /y /n "%PRINTER%"

echo Clearing stuck print jobs ...
powershell -NoProfile -Command "Get-PrintJob -PrinterName '%PRINTER%' -ErrorAction SilentlyContinue | Remove-PrintJob"

set "BROWSER="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "BROWSER=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined BROWSER (
  echo ERROR: Neither Google Chrome nor Microsoft Edge was found.
  pause
  exit /b 1
)

echo Launching Parking Manager in silent direct-print mode ...
start "" "%BROWSER%" --user-data-dir="%PROFILE_DIR%" --kiosk-printing --no-first-run --no-default-browser-check --app="%APP_URL%"
