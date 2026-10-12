
const parkingForm = document.getElementById("parkingForm");
const formSection = document.getElementById("formSection");
const receiptSection = document.getElementById("receiptSection");
const customerNameInput = document.getElementById("customerName");
const feeInput = document.getElementById("fee");

const printButton = document.getElementById("printButton");
const newReceiptButton = document.getElementById("newReceiptButton");
const backButton = document.getElementById("backButton");

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

parkingForm.addEventListener("submit", function (event) {
  event.preventDefault();

  const customerName = document
    .getElementById("customerName")
    .value.trim();

  const inTime = document.getElementById("inTime").value;
  const outTime = document.getElementById("outTime").value;
  const feeInput = document.getElementById("fee").value;
  const fee = parseFeeInput(feeInput);

  if (!customerName || !inTime || !outTime || feeInput === "") {
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

  document.getElementById("receiptNumber").textContent =
    generateReceiptNumber();

  document.getElementById("receiptDate").textContent =
    now.toLocaleDateString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });

  document.getElementById("receiptCustomer").textContent =
    customerName;

  document.getElementById("receiptInTime").textContent =
    formatTime(inTime);

  document.getElementById("receiptOutTime").textContent =
    formatTime(outTime);

  document.getElementById("receiptFee").textContent =
    formatFee(fee);

  formSection.classList.add("hidden");
  receiptSection.classList.remove("hidden");

  window.scrollTo({
    top: 0,
    behavior: "smooth",
  });
});

printButton.addEventListener("click", function () {
  window.print();
});

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
