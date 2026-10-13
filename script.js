
const parkingForm = document.getElementById("parkingForm");
const formSection = document.getElementById("formSection");
const receiptSection = document.getElementById("receiptSection");
const customerNameInput = document.getElementById("customerName");
const feeInput = document.getElementById("fee");

const printButton = document.getElementById("printButton");
const newReceiptButton = document.getElementById("newReceiptButton");
const backButton = document.getElementById("backButton");

// ─── Detect Tauri environment ────────────────────────────────────────────────
const IS_TAURI = typeof window.__TAURI__ !== "undefined" ||
                 typeof window.__TAURI_INTERNALS__ !== "undefined";

// ─── Local print service (print-agent on the POS PC) ─────────────────────────
const PRINT_AGENT_URL = "http://localhost:9123";
const PRINT_SERVICE_DOWNLOAD = "downloads/ParkingPrintService.zip";

let currentReceipt = null;

async function callPrintAgent(path, body, timeoutMs = 4000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(PRINT_AGENT_URL + path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(result.error || `Print service error (${response.status})`);
    }
    return result;
  } finally {
    clearTimeout(timer);
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatTime(timeValue) {
  const [hours, minutes] = timeValue.split(":");
  const date = new Date();
  date.setHours(Number(hours), Number(minutes), 0, 0);

  return date.toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: true,
  });
}

function formatFee(amount) {
  return (
    Number(amount).toLocaleString("en-ET", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }) + " ETB"
  );
}

function parseFeeInput(value) {
  const normalizedValue = value.trim();

  if (!/^\d+(\.\d{1,2})?$/.test(normalizedValue)) {
    return null;
  }

  const amount = Number(normalizedValue);

  if (!Number.isFinite(amount) || amount < 0) {
    return null;
  }

  return amount;
}

function isValidCustomerName(value) {
  return /^[A-Za-z][A-Za-z\s.'-]*$/.test(value.trim());
}

function generateReceiptNumber() {
  const now = new Date();
  const datePart = [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, "0"),
    String(now.getDate()).padStart(2, "0"),
  ].join("");

  const randomPart = Math.floor(1000 + Math.random() * 9000);

  return `PK-${datePart}-${randomPart}`;
}

// ─── Input sanitisation ───────────────────────────────────────────────────────

customerNameInput.addEventListener("input", function () {
  this.value = this.value.replace(/[^A-Za-z\s.'-]/g, "");
});

feeInput.addEventListener("input", function () {
  const rawValue = this.value.replace(/[^0-9.]/g, "");
  const parts = rawValue.split(".");

  if (parts.length > 2) {
    this.value = `${parts[0]}.${parts.slice(1).join("")}`;
    return;
  }

  if (parts.length === 2) {
    this.value = `${parts[0]}.${parts[1].slice(0, 2)}`;
    return;
  }

  this.value = rawValue;
});

// ─── Form submit ─────────────────────────────────────────────────────────────

parkingForm.addEventListener("submit", function (event) {
  event.preventDefault();

  const customerName = document
    .getElementById("customerName")
    .value.trim();

  const inTime = document.getElementById("inTime").value;
  const outTime = document.getElementById("outTime").value;
  const feeRaw = document.getElementById("fee").value;
  const fee = parseFeeInput(feeRaw);

  if (!customerName || !inTime || !outTime || feeRaw === "") {
    alert("Please fill in all the required fields.");
    return;
  }

  if (!isValidCustomerName(customerName)) {
    alert("Customer name should contain letters only, without numbers.");
    return;
  }

  if (fee === null) {
    alert("Please enter a valid parking fee, like 089 or 89.00.");
    return;
  }

  const now = new Date();

  currentReceipt = {
    receiptNo: generateReceiptNumber(),
    date: now.toLocaleDateString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    }),
    customer: customerName,
    inTime: formatTime(inTime),
    outTime: formatTime(outTime),
    fee,
    feeText: formatFee(fee),
  };

  document.getElementById("receiptNumber").textContent = currentReceipt.receiptNo;
  document.getElementById("receiptDate").textContent = currentReceipt.date;
  document.getElementById("receiptCustomer").textContent = currentReceipt.customer;
  document.getElementById("receiptInTime").textContent = currentReceipt.inTime;
  document.getElementById("receiptOutTime").textContent = currentReceipt.outTime;
  document.getElementById("receiptFee").textContent = currentReceipt.feeText;

  // Save the receipt on the POS PC (best effort; printing saves it again)
  callPrintAgent("/api/receipts", currentReceipt).catch((err) =>
    console.warn("Could not save receipt:", err),
  );

  formSection.classList.add("hidden");
  receiptSection.classList.remove("hidden");

  window.scrollTo({
    top: 0,
    behavior: "smooth",
  });
});

// ─── Thermal printing via tauri-plugin-thermal-printer ───────────────────────

/**
 * Build the structured ESC/POS print job from current receipt data
 * and send it directly to the default thermal printer (production mode).
 */
async function printWithTauriPlugin() {
  printButton.disabled = true;
  printButton.textContent = "Printing…";

  try {
    // Dynamically import from the Tauri-bundled ES module path
    const {
      list_thermal_printers,
      print_thermal_printer,
      title: titleSection,
      text,
      line,
      feed,
      cut,
    } = await import("/node_modules/tauri-plugin-thermal-printer/dist-js/index.js");

    // 1. Find the first available thermal printer
    const printers = await list_thermal_printers();

    if (!printers || printers.length === 0) {
      alert("No thermal printer found. Please connect your printer and try again.");
      return;
    }

    const printer = printers[0]; // Use first / default printer

    // 2. Read values already rendered on screen
    const receiptNo   = document.getElementById("receiptNumber").textContent;
    const receiptDate = document.getElementById("receiptDate").textContent;
    const customer    = document.getElementById("receiptCustomer").textContent;
    const inTimeVal   = document.getElementById("receiptInTime").textContent;
    const outTimeVal  = document.getElementById("receiptOutTime").textContent;
    const feeVal      = document.getElementById("receiptFee").textContent;

    // 3. Build ESC/POS sections
    const sections = [
      // Header
      titleSection("WASTINA COMMERCIAL CENTER", { align: "center" }),
      text("Thank you for parking with us!", { align: "center" }),
      line({ character: "-", length: 32 }),

      // Receipt details
      text(`Receipt No.  ${receiptNo}`,  { align: "left" }),
      text(`Date         ${receiptDate}`, { align: "left" }),
      line({ character: "-", length: 32 }),

      text(`Customer     ${customer}`,   { align: "left" }),
      text(`In-Time      ${inTimeVal}`,  { align: "left" }),
      text(`Out-Time     ${outTimeVal}`, { align: "left" }),
      line({ character: "-", length: 32 }),

      // Total
      titleSection(`TOTAL FEE  ${feeVal}`, { align: "center" }),
      line({ character: "=", length: 32 }),

      // Footer
      feed({ lines: 1 }),
      text("Please keep this receipt for your records.", { align: "center" }),
      text("Have a safe journey!", { align: "center" }),

      // Auto-cut
      feed({ lines: 3 }),
      cut({ mode: "partial", feed: 0 }),
    ];

    // 4. Send to printer
    await print_thermal_printer({
      printer_name: printer.name,
      paper_size: "Mm80",
      sections,
    });

    console.log("Print job sent successfully to:", printer.name);
  } catch (err) {
    console.error("Thermal print error:", err);
    alert("Printing failed: " + (err?.message ?? String(err)));
  } finally {
    printButton.disabled = false;
    printButton.textContent = "Print Receipt";
  }
}

// ─── Print button ─────────────────────────────────────────────────────────────

async function printWithAgent() {
  printButton.disabled = true;
  printButton.textContent = "Printing…";

  try {
    await callPrintAgent("/print", currentReceipt, 60000);
    printButton.textContent = "Printed ✓";
    setTimeout(() => {
      printButton.textContent = "Print Receipt";
    }, 2000);
  } catch (err) {
    console.error("Print service error:", err);
    printButton.textContent = "Print Receipt";

    if (err.name === "AbortError" || err instanceof TypeError) {
      const download = confirm(
        "The print service is not installed or not running on this computer " +
        "(or the browser blocked it).\n\n" +
        "Press OK to download the installer, then:\n" +
        "1. Extract the zip and run Setup.bat\n" +
        "2. Choose this PC's receipt printer\n" +
        "3. Press Print Receipt again (click Allow if the browser asks " +
        "to access devices on your local network).",
      );
      if (download) window.location.href = PRINT_SERVICE_DOWNLOAD;
    } else {
      alert("Printing failed: " + err.message);
    }
  } finally {
    printButton.disabled = false;
  }
}

printButton.addEventListener("click", function () {
  if (IS_TAURI) {
    // Desktop app: use thermal printer plugin directly — no dialog
    printWithTauriPlugin();
  } else {
    // Browser: send to the local print service — prints silently, no dialog
    printWithAgent();
  }
});

// ─── Navigation buttons ───────────────────────────────────────────────────────

backButton.addEventListener("click", function () {
  receiptSection.classList.add("hidden");
  formSection.classList.remove("hidden");

  document.getElementById("customerName").focus();

  window.scrollTo({
    top: 0,
    behavior: "smooth",
  });
});

newReceiptButton.addEventListener("click", function () {
  parkingForm.reset();

  receiptSection.classList.add("hidden");
  formSection.classList.remove("hidden");

  document.getElementById("customerName").focus();

  window.scrollTo({
    top: 0,
    behavior: "smooth",
  });
});
