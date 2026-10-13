@echo off
setlocal
title Parking Manager - Print Service Setup
set "SRC=%~dp0"
set "DEST=%LOCALAPPDATA%\ParkingPrintService"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass"

echo ============================================
echo   Parking Manager - Print Service Setup
echo ============================================
echo.
echo Installing to %DEST%
if not exist "%DEST%" mkdir "%DEST%"

if exist "%DEST%\agent.ps1" %PS% -File "%DEST%\agent.ps1" -Stop

copy /Y "%SRC%agent.ps1" "%DEST%\" >nul
copy /Y "%SRC%start-hidden.vbs" "%DEST%\" >nul
copy /Y "%SRC%Uninstall.bat" "%DEST%\" >nul
%PS% -Command "Get-ChildItem -LiteralPath '%DEST%' -File | Unblock-File"

%PS% -File "%DEST%\agent.ps1" -Setup %*
if errorlevel 1 (
  echo Setup did not finish.
  if "%~1"=="" pause
  exit /b 1
)

echo.
echo Registering the service to start automatically at login ...
%PS% -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Parking Print Service.lnk'); $s.TargetPath='wscript.exe'; $s.Arguments='\"%DEST%\start-hidden.vbs\"'; $s.WorkingDirectory='%DEST%'; $s.Save()"

echo Starting the service ...
wscript.exe "%DEST%\start-hidden.vbs"
ping -n 5 127.0.0.1 >nul

%PS% -Command "try { $h = Invoke-RestMethod http://localhost:9123/health -TimeoutSec 5; Write-Host ''; Write-Host ('SUCCESS: print service is running. Printer: ' + $h.printer) -ForegroundColor Green } catch { Write-Host ''; Write-Host 'WARNING: the service did not answer. See %DEST%\service.log' -ForegroundColor Red }"

echo.
echo You can now press "Print Receipt" on the Parking Manager website.
echo If the browser asks to access devices on your local network, click Allow.
echo To change the printer later, run this Setup again.
echo.
if "%~1"=="" pause
