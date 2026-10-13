// Parking Manager local print service.
// Runs on the POS PC, receives receipts from the deployed web app, prints them
// silently to the configured printer and stores them for the admin page.

import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(DIR, "data");
const CONFIG_FILE = path.join(DIR, "config.json");
const RECEIPTS_FILE = path.join(DATA_DIR, "receipts.json");
const PRINT_SCRIPT = path.join(DIR, "print-receipt.ps1");

const DEFAULT_CONFIG = {
  port: 9123,
  printerName: "HP LaserJet 400 M401 PCL 6",
  receiptWidthMm: 80,
  allowedOrigins: [
    "https://time-ticket-printer-src-tauri.vercel.app",
    "http://localhost",
    "http://127.0.0.1",
    "null",
  ],
  admin: null,
};

// ─── Config & storage ────────────────────────────────────────────────────────

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8").replace(/^﻿/, ""));
}

function loadConfig() {
  let config = { ...DEFAULT_CONFIG };
  if (fs.existsSync(CONFIG_FILE)) {
    config = { ...config, ...readJson(CONFIG_FILE) };
  }
  return config;
}

function saveConfig(config) {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
}

function hashPassword(password, salt = crypto.randomBytes(16).toString("hex")) {
  const hash = crypto.scryptSync(password, salt, 64).toString("hex");
  return { salt, hash };
}

function verifyPassword(password, admin) {
  if (!admin) return false;
  const { hash } = hashPassword(password, admin.salt);
  return crypto.timingSafeEqual(Buffer.from(hash, "hex"), Buffer.from(admin.hash, "hex"));
}

function loadReceipts() {
  if (!fs.existsSync(RECEIPTS_FILE)) return [];
  return readJson(RECEIPTS_FILE);
}

function saveReceipts(receipts) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const tmp = RECEIPTS_FILE + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(receipts, null, 2));
  fs.renameSync(tmp, RECEIPTS_FILE);
}

const RECEIPT_FIELDS = ["receiptNo", "date", "customer", "inTime", "outTime", "fee", "feeText"];

function upsertReceipt(input, { printed = false } = {}) {
  const receipt = {};
  for (const field of RECEIPT_FIELDS) {
    if (input[field] !== undefined) receipt[field] = input[field];
  }
  if (!receipt.receiptNo) throw new Error("receiptNo is required");

  const receipts = loadReceipts();
  const now = new Date().toISOString();
  let existing = receipts.find((r) => r.receiptNo === receipt.receiptNo);

  if (existing) {
    Object.assign(existing, receipt);
  } else {
    existing = { ...receipt, createdAt: now, printCount: 0 };
    receipts.push(existing);
  }

  if (printed) {
    existing.printCount = (existing.printCount || 0) + 1;
    existing.lastPrintedAt = now;
  }

  saveReceipts(receipts);
  return existing;
}

// ─── Printing ────────────────────────────────────────────────────────────────

function printReceipt(receipt, config) {
  const jobFile = path.join(os.tmpdir(), `parking-receipt-${crypto.randomUUID()}.json`);
  fs.writeFileSync(jobFile, JSON.stringify(receipt));

  return new Promise((resolve, reject) => {
    execFile(
      "powershell.exe",
      [
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", PRINT_SCRIPT,
        "-JobFile", jobFile,
        "-PrinterName", config.printerName,
        "-WidthMm", String(config.receiptWidthMm),
      ],
      { windowsHide: true, timeout: 60000 },
      (error, stdout, stderr) => {
        fs.rm(jobFile, { force: true }, () => {});
        if (error) {
          reject(new Error((stderr || stdout || error.message).trim()));
        } else {
          resolve();
        }
      },
    );
  });
}

// ─── HTTP helpers ────────────────────────────────────────────────────────────

const sessions = new Map(); // token -> expiry timestamp
const SESSION_MS = 12 * 60 * 60 * 1000;

function isAllowedOrigin(origin, config) {
  if (!origin) return true;
  return config.allowedOrigins.some(
    (allowed) => origin === allowed || origin.startsWith(allowed + ":"),
  );
}

function setCors(req, res, config) {
  const origin = req.headers.origin;
  if (origin && isAllowedOrigin(origin, config)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    // Chrome / Edge Private & Local Network Access preflight
    res.setHeader("Access-Control-Allow-Private-Network", "true");
    res.setHeader("Access-Control-Allow-Local-Network", "true");
  }
}

function sendJson(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 1e6) req.destroy();
    });
    req.on("end", () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", reject);
  });
}

function isAuthorized(req) {
  const token = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  const expiry = sessions.get(token);
  if (!expiry) return false;
  if (expiry < Date.now()) {
    sessions.delete(token);
    return false;
  }
  return true;
}

// ─── Routes ──────────────────────────────────────────────────────────────────

async function handle(req, res) {
  const config = loadConfig();
  setCors(req, res, config);

  if (req.headers.origin && !isAllowedOrigin(req.headers.origin, config)) {
    return sendJson(res, 403, { error: "Origin not allowed" });
  }

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    return res.end();
  }

  const { pathname } = new URL(req.url, "http://127.0.0.1");

  if (req.method === "GET" && pathname === "/health") {
    return sendJson(res, 200, { ok: true, printer: config.printerName });
  }

  if (req.method === "POST" && pathname === "/api/receipts") {
    const receipt = upsertReceipt(await readBody(req));
    return sendJson(res, 200, { ok: true, receipt });
  }

  if (req.method === "POST" && pathname === "/print") {
    const body = await readBody(req);
    const receipt = upsertReceipt(body);
    await printReceipt(receipt, config);
    upsertReceipt(body, { printed: true });
    return sendJson(res, 200, { ok: true, printer: config.printerName });
  }

  if (req.method === "POST" && pathname === "/api/login") {
    const { username, password } = await readBody(req);
    if (username !== config.admin?.username || !verifyPassword(String(password || ""), config.admin)) {
      return sendJson(res, 401, { error: "Invalid username or password" });
    }
    const token = crypto.randomBytes(32).toString("hex");
    sessions.set(token, Date.now() + SESSION_MS);
    return sendJson(res, 200, { ok: true, token });
  }

  if (pathname.startsWith("/api/") && !isAuthorized(req)) {
    return sendJson(res, 401, { error: "Not logged in" });
  }

  if (req.method === "GET" && pathname === "/api/receipts") {
    const receipts = loadReceipts().sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    return sendJson(res, 200, { ok: true, receipts });
  }

  if (req.method === "POST" && pathname === "/api/change-password") {
    const { currentPassword, newPassword } = await readBody(req);
    if (!verifyPassword(String(currentPassword || ""), config.admin)) {
      return sendJson(res, 400, { error: "Current password is wrong" });
    }
    if (!newPassword || String(newPassword).length < 6) {
      return sendJson(res, 400, { error: "New password must be at least 6 characters" });
    }
    config.admin = { username: config.admin.username, ...hashPassword(String(newPassword)) };
    saveConfig(config);
    return sendJson(res, 200, { ok: true });
  }

  return sendJson(res, 404, { error: "Not found" });
}

// ─── CLI: node server.js --set-admin <username> <password> ──────────────────

const args = process.argv.slice(2);

if (args[0] === "--set-admin") {
  const [, username, password] = args;
  if (!username || !password) {
    console.error("Usage: node server.js --set-admin <username> <password>");
    process.exit(1);
  }
  const config = loadConfig();
  config.admin = { username, ...hashPassword(password) };
  saveConfig(config);
  console.log(`Admin user "${username}" saved to ${CONFIG_FILE}`);
  process.exit(0);
}

const config = loadConfig();
if (!fs.existsSync(CONFIG_FILE)) saveConfig(config);

http
  .createServer((req, res) => {
    handle(req, res).catch((err) => {
      console.error(err);
      sendJson(res, 500, { error: err.message });
    });
  })
  .listen(config.port, "127.0.0.1", () => {
    console.log(`Parking Manager print service on http://127.0.0.1:${config.port}`);
    console.log(`Printer: ${config.printerName}`);
  });
