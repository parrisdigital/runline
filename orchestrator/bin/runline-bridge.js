#!/usr/bin/env node

import { spawn } from "node:child_process";
import { networkInterfaces } from "node:os";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const command = process.argv[2] ?? "up";
const args = process.argv.slice(3);

if (command === "--help" || command === "-h" || command === "help") {
  printHelp();
  process.exit(0);
}

if (command === "--version" || command === "-v" || command === "version") {
  const packageJsonPath = join(dirname(fileURLToPath(import.meta.url)), "..", "package.json");
  const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8"));
  console.log(packageJson.version);
  process.exit(0);
}

if (command !== "up") {
  console.error(`Unknown command: ${command}`);
  printHelp();
  process.exit(2);
}

const port = valueAfter("--port") ?? process.env.PORT ?? "8787";
const keepAwakeRequested = hasFlag("--keep-awake") || isTruthy(process.env.RUNLINE_BRIDGE_KEEP_AWAKE);
const keepAwakeActive = startKeepAwake(keepAwakeRequested);

process.env.PORT = port;
process.env.RUNLINE_BRIDGE_KEEP_AWAKE_ACTIVE = keepAwakeActive ? "true" : "false";

printStartup(port, keepAwakeRequested, keepAwakeActive);
await import("../dist/server.js");

function hasFlag(name) {
  return args.includes(name);
}

function valueAfter(name) {
  const index = args.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return args[index + 1];
}

function isTruthy(value) {
  return ["1", "true", "yes", "on"].includes(String(value ?? "").trim().toLowerCase());
}

function startKeepAwake(requested) {
  if (!requested) {
    return false;
  }

  if (process.platform !== "darwin") {
    console.warn("Keep Awake is only available on macOS. Continuing without caffeinate.");
    return false;
  }

  const caffeinate = spawn("caffeinate", ["-imsu", "-w", String(process.pid)], {
    stdio: "ignore",
    detached: false,
  });

  caffeinate.on("error", (error) => {
    console.warn(`Could not start macOS caffeinate: ${error.message}`);
  });
  caffeinate.unref();
  return true;
}

function printHelp() {
  console.log(`
Runline Bridge

Usage:
  runline-bridge up [--port 8787] [--keep-awake]

Environment:
  CURSOR_API_KEY                  Cursor API key used when the iOS app does not send one per request.
  RUNLINE_SDK_MCP_PROFILES        JSON array of MCP/subagent profiles exposed to Runline.
  RUNLINE_BRIDGE_DISABLE_PAIRING  Set to true for local development only.
  RUNLINE_BRIDGE_KEEP_AWAKE       Set to true to keep macOS awake while the bridge runs.
`);
}

function printStartup(port, keepAwakeRequested, keepAwakeActive) {
  const lanURL = firstLANAddress()
    ? `http://${firstLANAddress()}:${port}`
    : undefined;

  console.log("Runline Bridge");
  console.log("");
  console.log(`Local URL: http://localhost:${port}`);
  if (lanURL) {
    console.log(`iPhone URL: ${lanURL}`);
  }
  if (keepAwakeRequested) {
    console.log(`Keep Awake: ${keepAwakeActive ? "enabled" : "unavailable"}`);
  } else {
    console.log("Keep Awake: disabled");
  }
  console.log("");
  console.log("In Runline on iPhone:");
  console.log("  Settings -> Cursor SDK -> Enable Runline Bridge");
  console.log("  Enter the iPhone URL, tap Start Pairing, then enter the terminal code.");
  console.log("");
}

function firstLANAddress() {
  for (const addresses of Object.values(networkInterfaces())) {
    for (const address of addresses ?? []) {
      if (address.family === "IPv4" && !address.internal) {
        return address.address;
      }
    }
  }
  return undefined;
}
