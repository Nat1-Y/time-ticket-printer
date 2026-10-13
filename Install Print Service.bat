@echo off
title Parking Manager - Install Print Service
set "AGENT_DIR=%~dp0print-agent"

where node >nul 2>nul
if errorlevel 1 (
  echo ERROR: Node.js is not installed. Install it from https://nodejs.org and run this again.
  pause
  exit /b 1
)

echo Stopping any running print service ...
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='node.exe'\" | Where-Object CommandLine -match 'print-agent' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"

echo Registering print service to start with Windows ...
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Parking Print Service.lnk'); $s.TargetPath='wscript.exe'; $s.Arguments='\"%AGENT_DIR%\start-hidden.vbs\"'; $s.WorkingDirectory='%AGENT_DIR%'; $s.Save()"

echo Starting print service ...
wscript.exe "%AGENT_DIR%\start-hidden.vbs"

echo.
echo Done. The print service is running and will start automatically at login.
echo Receipts print to the printer set in print-agent\config.json
pause
