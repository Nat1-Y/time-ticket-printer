
const parkingForm = document.getElementById("parkingForm");
const formSection = document.getElementById("formSection");
const receiptSection = document.getElementById("receiptSection");

const printButton = document.getElementById("printButton");
const newReceiptButton = document.getElementById("newReceiptButton");

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

parkingForm.addEventListener("submit", function (event) {
  event.preventDefault();

  const customerName = document
    .getElementById("customerName")
    .value.trim();

  const inTime = document.getElementById("inTime").value;
  const outTime = document.getElementById("outTime").value;
  const fee = document.getElementById("fee").value;

  if (!customerName || !inTime || !outTime || fee === "") {
    alert("Please fill in all the required fields.");
    return;
  }

  if (!Number.isFinite(Number(fee)) || Number(fee) < 0) {
    alert("Please enter a valid parking fee.");
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
