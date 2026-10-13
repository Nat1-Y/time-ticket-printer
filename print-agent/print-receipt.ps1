param(
  [Parameter(Mandatory = $true)][string]$JobFile,
  [Parameter(Mandatory = $true)][string]$PrinterName,
  [double]$WidthMm = 80
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$receipt = Get-Content -Raw -Encoding UTF8 -Path $JobFile | ConvertFrom-Json

$doc = New-Object System.Drawing.Printing.PrintDocument
$doc.PrinterSettings.PrinterName = $PrinterName
if (-not $doc.PrinterSettings.IsValid) {
  throw "Printer '$PrinterName' was not found. Check the printer name in print-agent\config.json."
}
$doc.DocumentName = "Parking Receipt $($receipt.receiptNo)"
# No "Printing..." status window
$doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController

$doc.add_PrintPage({
  param($sender, $e)

  $g = $e.Graphics
  $g.PageUnit = [System.Drawing.GraphicsUnit]::Millimeter
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

  $x = 5.0
  $y = 5.0
  $w = $WidthMm

  $fontTitle  = New-Object System.Drawing.Font("Arial", 13, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
  $fontSmall  = New-Object System.Drawing.Font("Arial", 8,  [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
  $fontLabel  = New-Object System.Drawing.Font("Arial", 9,  [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
  $fontValue  = New-Object System.Drawing.Font("Arial", 9,  [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
  $fontTotal  = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
  $fontLogo   = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)

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
  $logo = 10.0
  $logoX = $x + ($w - $logo) / 2
  $g.FillEllipse($black, [single]$logoX, [single]$y, [single]$logo, [single]$logo)
  $g.DrawString("P", $fontLogo, $white, (New-Object System.Drawing.RectangleF([single]$logoX, [single]$y, [single]$logo, [single]$logo)), $center)
  $y += $logo + 3

  function Write-Centered($text, $font) {
    $h = $font.GetHeight($g)
    $g.DrawString($text, $font, $black, (New-Object System.Drawing.RectangleF([single]$x, [single]$script:y, [single]$w, [single]$h)), $center)
    $script:y += $h + 1
  }

  function Write-Divider {
    $script:y += 2
    $g.DrawLine($dash, [single]$x, [single]$script:y, [single]($x + $w), [single]$script:y)
    $script:y += 3
  }

  function Write-Row($label, $value, $labelFont, $valueFont) {
    $h = [Math]::Max($labelFont.GetHeight($g), $valueFont.GetHeight($g))
    $g.DrawString($label, $labelFont, $black, [single]$x, [single]$script:y)
    $g.DrawString([string]$value, $valueFont, $black, (New-Object System.Drawing.RectangleF([single]$x, [single]$script:y, [single]$w, [single]$h)), $right)
    $script:y += $h + 2
  }

  $script:y = $y
  Write-Centered "PARKING RECEIPT" $fontTitle
  Write-Centered "Thank you for parking with us!" $fontSmall
  Write-Divider
  Write-Row "Receipt No." $receipt.receiptNo $fontLabel $fontValue
  Write-Row "Date" $receipt.date $fontLabel $fontValue
  Write-Divider
  Write-Row "Customer" $receipt.customer $fontLabel $fontValue
  Write-Row "In-Time" $receipt.inTime $fontLabel $fontValue
  Write-Row "Out-Time" $receipt.outTime $fontLabel $fontValue
  Write-Divider
  Write-Row "TOTAL FEE" $receipt.feeText $fontTotal $fontTotal
  $script:y += 3
  Write-Centered "Please keep this receipt for your records." $fontSmall
  Write-Centered "Have a safe journey!" $fontSmall

  $e.HasMorePages = $false
})

$doc.Print()
$doc.Dispose()
Write-Output "Printed $($receipt.receiptNo) on $PrinterName"
