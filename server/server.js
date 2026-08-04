#!/usr/bin/env node
"use strict";

const { existsSync } = require("node:fs");
const { join } = require("node:path");
const { spawn } = require("node:child_process");

const cliPath = join(__dirname, "dist", "cli.mjs");
if (!existsSync(cliPath)) {
  console.error("[nexus] Missing server/dist/cli.mjs; run `npm run build` first.");
  process.exit(1);
}

const requestedArgs = process.argv.slice(2);
const command = requestedArgs[0] && !requestedArgs[0].startsWith("-")
  ? requestedArgs
  : ["start", "--foreground", ...requestedArgs];

const child = spawn(process.execPath, [cliPath, ...command], {
  stdio: "inherit",
  windowsHide: true,
  shell: false,
});

const forwardSignal = (signal) => {
  if (!child.killed) child.kill(signal);
};
process.once("SIGINT", () => forwardSignal("SIGINT"));
process.once("SIGTERM", () => forwardSignal("SIGTERM"));

child.once("error", (error) => {
  console.error(`[nexus] Failed to start canonical CLI: ${error.message}`);
  process.exitCode = 1;
});

child.once("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
  } else {
    process.exitCode = code ?? 1;
  }
});
