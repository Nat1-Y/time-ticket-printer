PARKING MANAGER - PRINT SERVICE
===============================

Lets the Parking Manager website print receipts directly to this PC's
printer, without the browser print dialog, and saves every receipt for
the Admin page.

INSTALL (once per PC)
  1. Extract this zip.
  2. Double-click Setup.bat.
  3. Pick the receipt printer by number (choose one marked
     [USB CONNECTED]), enter the paper width (58 or 80) for thermal
     printers, and create the admin login.
  4. Open the Parking Manager website and press "Print Receipt".
     If the browser asks to access devices on your local network,
     click Allow.

The service starts automatically every time Windows starts.
Thermal printers get the receipt exactly like the screen and the
paper is cut automatically after each receipt (if the printer has
a cutter). If you plug the printer into another USB socket, the
service finds it automatically.

CHANGE PRINTER  - run Setup.bat again.
REMOVE          - run %LOCALAPPDATA%\ParkingPrintService\Uninstall.bat
SAVED RECEIPTS  - %LOCALAPPDATA%\ParkingPrintService\data\receipts.json
LOG             - %LOCALAPPDATA%\ParkingPrintService\service.log

Works on Windows 10 / 11. Nothing else needs to be installed.
