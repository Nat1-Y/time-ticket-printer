# Rebuilds downloads/ParkingPrintService.zip (served by the website).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path (Split-Path -Parent $here) "downloads\ParkingPrintService.zip"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
$files = "agent.ps1", "start-hidden.vbs", "Setup.bat", "Uninstall.bat", "README.txt" | ForEach-Object { Join-Path $here $_ }
Compress-Archive -Path $files -DestinationPath $out -Force
Write-Output "Built $out"
