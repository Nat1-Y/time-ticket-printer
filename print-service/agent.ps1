# Parking Manager print service.
# Runs hidden on each POS PC. The deployed web app sends receipts to
# http://localhost:9123, this service prints them silently (no dialog) on the
# chosen printer and stores them for the admin page.
#
#   agent.ps1          run the service
#   agent.ps1 -Setup   choose printer / admin login (interactive)
#   agent.ps1 -Stop    stop a running service
#
# Unattended setup (for installing on many PCs):
#   agent.ps1 -Setup -Quiet -Printer "XP-58" -AdminUser admin -AdminPassword secret [-TestPrint]

param(
  [switch]$Setup,
  [switch]$Stop,
  [switch]$Quiet,
  [switch]$TestPrint,
  [string]$Printer,
  [string]$AdminUser,
  [string]$AdminPassword
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$Dir          = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile   = Join-Path $Dir "config.json"
$DataDir      = Join-Path $Dir "data"
$ReceiptsFile = Join-Path $DataDir "receipts.json"
$LogFile      = Join-Path $Dir "service.log"
$Utf8         = New-Object System.Text.UTF8Encoding $false
$Port         = 9123

$DefaultOrigins = @(
  "https://time-ticket-printer-src-tauri.vercel.app",
  "http://localhost",
  "http://127.0.0.1",
  "null"
)

# --- Files -------------------------------------------------------------------

function Write-Log($message) {
  $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $message
  try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch {}
}

function Read-JsonFile($path) {
  if (-not (Test-Path $path)) { return $null }
  $text = [IO.File]::ReadAllText($path, $Utf8)
  if (-not $text.Trim()) { return $null }
  return ConvertFrom-Json $text
}

function Write-JsonFile($path, $object) {
  $json = ConvertTo-Json -InputObject $object -Depth 6
  $tmp = "$path.tmp"
  [IO.File]::WriteAllText($tmp, $json, $Utf8)
  if (Test-Path $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}

function Get-Config {
  $config = Read-JsonFile $ConfigFile
  if ($null -eq $config) { $config = New-Object PSObject }
  if ($null -eq $config.printerName)    { $config | Add-Member -Force printerName "" }
  if ($null -eq $config.receiptWidthMm) { $config | Add-Member -Force receiptWidthMm 72 }
  if ($null -eq $config.allowedOrigins) { $config | Add-Member -Force allowedOrigins $DefaultOrigins }
  if ($null -eq $config.admin)          { $config | Add-Member -Force admin $null }
  return $config
}

function Get-Receipts {
  $list = New-Object System.Collections.ArrayList
  $data = Read-JsonFile $ReceiptsFile
  if ($null -ne $data) { foreach ($r in @($data)) { [void]$list.Add($r) } }
  return ,$list
}

function Save-Receipts($list) {
  if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }
  Write-JsonFile $ReceiptsFile @($list.ToArray())
}

function Get-IsoNow { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }

$ReceiptFields = @("receiptNo", "date", "customer", "inTime", "outTime", "fee", "feeText")

function Save-Receipt($data, [bool]$printed) {
  if (-not $data.receiptNo) { throw "receiptNo is required" }

  $list = Get-Receipts
  $existing = $null
  foreach ($r in $list) { if ($r.receiptNo -eq $data.receiptNo) { $existing = $r; break } }

  if ($null -eq $existing) {
    $existing = New-Object PSObject
    foreach ($f in $ReceiptFields) { $existing | Add-Member -Force $f $data.$f }
    $existing | Add-Member -Force createdAt (Get-IsoNow)
    $existing | Add-Member -Force printCount 0
    [void]$list.Add($existing)
  } else {
    foreach ($f in $ReceiptFields) {
      if ($null -ne $data.$f) { $existing | Add-Member -Force $f $data.$f }
    }
  }

  if ($printed) {
    $existing | Add-Member -Force printCount ([int]$existing.printCount + 1)
    $existing | Add-Member -Force lastPrintedAt (Get-IsoNow)
  }

  Save-Receipts $list
  return $existing
}

# --- Passwords ---------------------------------------------------------------

function ConvertTo-Hex([byte[]]$bytes) { ([BitConverter]::ToString($bytes)).Replace("-", "") }

function ConvertFrom-Hex([string]$hex) {
  $bytes = New-Object byte[] ($hex.Length / 2)
  for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }
  return ,$bytes
}

function New-PasswordHash([string]$password, [string]$saltHex) {
  if ($saltHex) {
    $salt = ConvertFrom-Hex $saltHex
  } else {
    $salt = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
  }
  $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($password, $salt, 100000)
  return @{ salt = (ConvertTo-Hex $salt); hash = (ConvertTo-Hex $kdf.GetBytes(32)) }
}

function Test-Password([string]$password, $admin) {
  if ($null -eq $admin -or -not $admin.salt) { return $false }
  $candidate = (New-PasswordHash $password $admin.salt).hash
  $diff = $candidate.Length -bxor $admin.hash.Length
  for ($i = 0; $i -lt [Math]::Min($candidate.Length, $admin.hash.Length); $i++) {
    $diff = $diff -bor ([int][char]$candidate[$i] -bxor [int][char]$admin.hash[$i])
  }
  return $diff -eq 0
}

# --- Printing ----------------------------------------------------------------

function Invoke-PrintReceipt($receipt, $config) {
  $doc = New-Object System.Drawing.Printing.PrintDocument
  if ($config.printerName) { $doc.PrinterSettings.PrinterName = $config.printerName }
  if (-not $doc.PrinterSettings.IsValid) {
    throw "Printer '$($config.printerName)' was not found. Run Setup again to choose a printer."
  }
  $doc.DocumentName = "Parking Receipt $($receipt.receiptNo)"
  $doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController

  # Roll printers (58/80 mm) report a page meters long; use a receipt-sized page
  # so the printer doesn't feed blank paper after the receipt.
  $paper = $doc.DefaultPageSettings.PaperSize
  if ($paper.Width -le 320) {
    $doc.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize("Receipt", $paper.Width, 512)
  }

  $script:PrintJob = @{ receipt = $receipt; maxWidthMm = [double]$config.receiptWidthMm }

  $doc.add_PrintPage({
    param($sender, $e)

    $job = $script:PrintJob
    $r = $job.receipt
    $g = $e.Graphics
    $g.PageUnit = [System.Drawing.GraphicsUnit]::Millimeter
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # Fit the receipt to the paper: narrow thermal rolls vs. A4 laser pages
    $printableMm = $e.PageSettings.PrintableArea.Width * 0.254
    if ($printableMm -lt 70) { $x = 1.0 } else { $x = 5.0 }
    $w = [Math]::Min($job.maxWidthMm, $printableMm - 2 * $x)
    if ($w -lt 60) { $scale = 0.8 } else { $scale = 1.0 }
    $y = 3.0

    $bold = [System.Drawing.FontStyle]::Bold
    $regular = [System.Drawing.FontStyle]::Regular
    $pt = [System.Drawing.GraphicsUnit]::Point
    $fontTitle = New-Object System.Drawing.Font("Arial", (13 * $scale), $bold, $pt)
    $fontSmall = New-Object System.Drawing.Font("Arial", (8 * $scale), $regular, $pt)
    $fontLabel = New-Object System.Drawing.Font("Arial", (9 * $scale), $regular, $pt)
    $fontValue = New-Object System.Drawing.Font("Arial", (9 * $scale), $bold, $pt)
    $fontTotal = New-Object System.Drawing.Font("Arial", (12 * $scale), $bold, $pt)
    $fontLogo  = New-Object System.Drawing.Font("Arial", (14 * $scale), $bold, $pt)

    $black = [System.Drawing.Brushes]::Black
    $white = [System.Drawing.Brushes]::White

    $center = New-Object System.Drawing.StringFormat
    $center.Alignment = [System.Drawing.StringAlignment]::Center
    $center.LineAlignment = [System.Drawing.StringAlignment]::Center
    $right = New-Object System.Drawing.StringFormat
    $right.Alignment = [System.Drawing.StringAlignment]::Far

    $dash = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 0.3)
    $dash.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

    # Logo
    $logo = 10.0 * $scale
    $logoX = $x + ($w - $logo) / 2
    $g.FillEllipse($black, [single]$logoX, [single]$y, [single]$logo, [single]$logo)
    $g.DrawString("P", $fontLogo, $white, (New-Object System.Drawing.RectangleF([single]$logoX, [single]$y, [single]$logo, [single]$logo)), $center)
    $y += $logo + 3

    $layout = New-Object System.Drawing.SizeF([single]$w, [single]1000)

    $centered = {
      param($text, $font)
      $h = $g.MeasureString($text, $font, $layout, $center).Height
      $g.DrawString($text, $font, $black, (New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$w, [single]$h)), $center)
      return $y + $h + 1
    }

    $divider = {
      $yy = $y + 2
      $g.DrawLine($dash, [single]$x, [single]$yy, [single]($x + $w), [single]$yy)
      return $yy + 3
    }

    $row = {
      param($label, $value, $labelFont, $valueFont)
      $value = [string]$value
      $h = [Math]::Max($labelFont.GetHeight($g), $valueFont.GetHeight($g))
      $lw = $g.MeasureString($label, $labelFont).Width
      $vw = $g.MeasureString($value, $valueFont).Width
      $g.DrawString($label, $labelFont, $black, [single]$x, [single]$y)
      $yy = $y
      if ($lw + $vw + 2 -gt $w) { $yy += $h }
      $g.DrawString($value, $valueFont, $black, (New-Object System.Drawing.RectangleF([single]$x, [single]$yy, [single]$w, [single]$h)), $right)
      return $yy + $h + 2
    }

    $y = & $centered "PARKING RECEIPT" $fontTitle
    $y = & $centered "Thank you for parking with us!" $fontSmall
    $y = & $divider
    $y = & $row "Receipt No." $r.receiptNo $fontLabel $fontValue
    $y = & $row "Date" $r.date $fontLabel $fontValue
    $y = & $divider
    $y = & $row "Customer" $r.customer $fontLabel $fontValue
    $y = & $row "In-Time" $r.inTime $fontLabel $fontValue
    $y = & $row "Out-Time" $r.outTime $fontLabel $fontValue
    $y = & $divider
    $y = & $row "TOTAL FEE" $r.feeText $fontTotal $fontTotal
    $y += 3
    $y = & $centered "Please keep this receipt for your records." $fontSmall
    $y = & $centered "Have a safe journey!" $fontSmall

    $e.HasMorePages = $false
  })

  try {
    $doc.Print()
  } finally {
    $doc.Dispose()
  }
  return $doc.PrinterSettings.PrinterName
}

# --- -Stop -------------------------------------------------------------------

if ($Stop) {
  Get-CimInstance Win32_Process -Filter "name='powershell.exe'" |
    Where-Object { $_.CommandLine -match "agent\.ps1" -and $_.CommandLine -notmatch "-Setup|-Stop" -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  exit 0
}

# --- -Setup (interactive) ----------------------------------------------------

if ($Setup) {
  $config = Get-Config

  $defaultPrinter = (New-Object System.Drawing.Printing.PrinterSettings).PrinterName
  $printers = @([System.Drawing.Printing.PrinterSettings]::InstalledPrinters)
  $current = $config.printerName
  if (-not $current) { $current = $defaultPrinter }

  Write-Host ""
  Write-Host "Printers on this PC:" -ForegroundColor Cyan
  for ($i = 0; $i -lt $printers.Count; $i++) {
    $mark = ""
    if ($printers[$i] -eq $current) { $mark = "   <- current" }
    Write-Host ("  {0,2}. {1}{2}" -f ($i + 1), $printers[$i], $mark)
  }
  Write-Host ""
  if ($Printer) {
    if ($printers -notcontains $Printer) { Write-Host "Printer '$Printer' not found." -ForegroundColor Red; exit 1 }
    $current = $Printer
  } elseif (-not $Quiet) {
    $choice = Read-Host "Number of the receipt printer (Enter = keep '$current')"
    if ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $printers.Count) {
      $current = $printers[[int]$choice - 1]
    }
  }
  $config.printerName = $current
  Write-Host "Receipts will print on: $current" -ForegroundColor Green

  if ($AdminPassword) {
    if ($AdminPassword.Length -lt 6) { Write-Host "Admin password must be at least 6 characters." -ForegroundColor Red; exit 1 }
    if (-not $AdminUser) { $AdminUser = "admin" }
    $h = New-PasswordHash $AdminPassword
    $config.admin = [PSCustomObject]@{ username = $AdminUser; salt = $h.salt; hash = $h.hash }
  }

  $setAdmin = -not $AdminPassword -and -not ($Quiet -and $config.admin)
  if ($setAdmin -and $config.admin -and -not $Quiet) {
    $answer = Read-Host "Keep the existing admin login '$($config.admin.username)'? (Y/n)"
    $setAdmin = $answer -match "^[nN]"
  }
  if ($setAdmin) {
    Write-Host ""
    Write-Host "Create the admin login for the Admin page on this PC." -ForegroundColor Cyan
    $username = Read-Host "Admin username (Enter = admin)"
    if (-not $username) { $username = "admin" }
    while ($true) {
      $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host "Admin password (min 6 characters)" -AsSecureString)))
      $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host "Repeat password" -AsSecureString)))
      if ($p1.Length -lt 6) { Write-Host "Password too short." -ForegroundColor Yellow; continue }
      if ($p1 -ne $p2) { Write-Host "Passwords do not match." -ForegroundColor Yellow; continue }
      break
    }
    $h = New-PasswordHash $p1
    $config.admin = [PSCustomObject]@{ username = $username; salt = $h.salt; hash = $h.hash }
  }

  Write-JsonFile $ConfigFile $config

  if ($Quiet) { $test = "" } else { $test = Read-Host "Print a test receipt now? (y/N)" }
  if ($TestPrint -or $test -match "^[yY]") {
    $sample = [PSCustomObject]@{
      receiptNo = "TEST-PRINT"; date = (Get-Date -Format "dd MMM yyyy"); customer = "Test"
      inTime = "08:00 AM"; outTime = "09:00 AM"; fee = 0; feeText = "0.00 ETB"
    }
    try {
      $name = Invoke-PrintReceipt $sample $config
      Write-Host "Test receipt sent to $name" -ForegroundColor Green
    } catch {
      Write-Host "Test print failed: $($_.Exception.Message)" -ForegroundColor Red
    }
  }
  exit 0
}

# --- HTTP service ------------------------------------------------------------

$Sessions = @{}

function Test-Origin($origin, $config) {
  if (-not $origin) { return $true }
  foreach ($allowed in @($config.allowedOrigins)) {
    if ($origin -eq $allowed -or $origin.StartsWith("$($allowed):")) { return $true }
  }
  return $false
}

function Send-Json($ctx, [int]$status, $body) {
  $res = $ctx.Response
  $res.StatusCode = $status
  $res.ContentType = "application/json; charset=utf-8"
  $bytes = $Utf8.GetBytes((ConvertTo-Json -InputObject $body -Depth 6 -Compress))
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.Close()
}

function Read-Body($req) {
  $reader = New-Object IO.StreamReader($req.InputStream, $Utf8)
  $text = $reader.ReadToEnd()
  $reader.Close()
  if (-not $text.Trim()) { return New-Object PSObject }
  return ConvertFrom-Json $text
}

function Test-Session($req) {
  $token = ([string]$req.Headers["Authorization"]) -replace "^Bearer\s+", ""
  if (-not $token -or -not $Sessions.ContainsKey($token)) { return $false }
  if ($Sessions[$token] -lt (Get-Date)) { $Sessions.Remove($token); return $false }
  return $true
}

function Invoke-Request($ctx) {
  $req = $ctx.Request
  $res = $ctx.Response
  $config = Get-Config
  $origin = $req.Headers["Origin"]

  if ($origin -and (Test-Origin $origin $config)) {
    $res.AddHeader("Access-Control-Allow-Origin", $origin)
    $res.AddHeader("Vary", "Origin")
    $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $res.AddHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
    # Chrome / Edge Private & Local Network Access preflight
    $res.AddHeader("Access-Control-Allow-Private-Network", "true")
    $res.AddHeader("Access-Control-Allow-Local-Network", "true")
  } elseif ($origin) {
    return Send-Json $ctx 403 @{ error = "Origin not allowed" }
  }

  if ($req.HttpMethod -eq "OPTIONS") {
    $res.StatusCode = 204
    $res.Close()
    return
  }

  $path = $req.Url.AbsolutePath
  $method = $req.HttpMethod

  if ($method -eq "GET" -and $path -eq "/health") {
    $printer = $config.printerName
    if (-not $printer) { $printer = (New-Object System.Drawing.Printing.PrinterSettings).PrinterName }
    return Send-Json $ctx 200 @{ ok = $true; printer = $printer }
  }

  if ($method -eq "POST" -and $path -eq "/api/receipts") {
    $receipt = Save-Receipt (Read-Body $req) $false
    return Send-Json $ctx 200 @{ ok = $true; receipt = $receipt }
  }

  if ($method -eq "POST" -and $path -eq "/print") {
    $body = Read-Body $req
    $receipt = Save-Receipt $body $false
    $printer = Invoke-PrintReceipt $receipt $config
    [void](Save-Receipt $body $true)
    Write-Log "Printed $($receipt.receiptNo) on $printer"
    return Send-Json $ctx 200 @{ ok = $true; printer = $printer }
  }

  if ($method -eq "POST" -and $path -eq "/api/login") {
    $body = Read-Body $req
    if (-not $config.admin -or $body.username -ne $config.admin.username -or -not (Test-Password ([string]$body.password) $config.admin)) {
      return Send-Json $ctx 401 @{ error = "Invalid username or password" }
    }
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $token = ConvertTo-Hex $bytes
    $Sessions[$token] = (Get-Date).AddHours(12)
    return Send-Json $ctx 200 @{ ok = $true; token = $token }
  }

  if ($path.StartsWith("/api/") -and -not (Test-Session $req)) {
    return Send-Json $ctx 401 @{ error = "Not logged in" }
  }

  if ($method -eq "GET" -and $path -eq "/api/receipts") {
    $list = Get-Receipts
    $sorted = @($list | Sort-Object -Property createdAt -Descending)
    return Send-Json $ctx 200 @{ ok = $true; receipts = $sorted }
  }

  if ($method -eq "POST" -and $path -eq "/api/change-password") {
    $body = Read-Body $req
    if (-not (Test-Password ([string]$body.currentPassword) $config.admin)) {
      return Send-Json $ctx 400 @{ error = "Current password is wrong" }
    }
    if (([string]$body.newPassword).Length -lt 6) {
      return Send-Json $ctx 400 @{ error = "New password must be at least 6 characters" }
    }
    $h = New-PasswordHash ([string]$body.newPassword)
    $config.admin = [PSCustomObject]@{ username = $config.admin.username; salt = $h.salt; hash = $h.hash }
    Write-JsonFile $ConfigFile $config
    return Send-Json $ctx 200 @{ ok = $true }
  }

  return Send-Json $ctx 404 @{ error = "Not found" }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
try {
  $listener.Start()
} catch {
  # 127.0.0.1 needs an admin URL reservation on some PCs; localhost never does
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add("http://localhost:$Port/")
  try {
    $listener.Start()
  } catch {
    Write-Log "Could not start on port $Port (already running?): $($_.Exception.Message)"
    exit 1
  }
}

Write-Log "Print service started on http://localhost:$Port"

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  try {
    Invoke-Request $ctx
  } catch {
    Write-Log "Error: $($_.Exception.Message)"
    try { Send-Json $ctx 500 @{ error = $_.Exception.Message } } catch {}
  }
}
