import { startWatcher, stopWatcher, scanLocalSessionStatuses } from "./dist/discovery/session-watcher.mjs";

console.log("=================================================");
console.log("  OpenCode Live Session Watcher (60s Duration)  ");
console.log("=================================================");
console.log(`Started at: ${new Date().toLocaleTimeString()}`);
console.log("Listening for OpenCode session additions/changes...\n");

// Initial scan snapshot
try {
  const initial = await scanLocalSessionStatuses();
  const opencodeInitial = initial.filter((s) => s.agentName === "opencode");
  console.log(`[Initial Scan] Found ${opencodeInitial.length} OpenCode items:`);
  for (const s of opencodeInitial) {
    console.log(`  - ID: ${s.sessionId} | Status: ${s.status} | LastActivity: ${new Date(s.lastActivity).toLocaleTimeString()}`);
  }
} catch (err) {
  console.error(`[Initial Scan Error] ${err.message}`);
}

console.log("\n>>> WAITING FOR YOU TO START AN OPENCODE SESSION... <<<\n");

const onChange = (added, removed, changed) => {
  const opencodeAdded = added.filter((s) => s.agentName === "opencode");
  const opencodeChanged = changed.filter((s) => s.agentName === "opencode");
  const opencodeRemoved = removed.filter((s) => s.agentName === "opencode");

  if (opencodeAdded.length > 0) {
    console.log(`\n🚨 [${new Date().toLocaleTimeString()}] DETECTED NEW OPENCODE SESSION! (ADDED)`);
    for (const s of opencodeAdded) {
      console.log(`   ➜ SessionId: ${s.sessionId} | Status: ${s.status} | Time: ${new Date(s.lastActivity).toLocaleTimeString()}`);
    }
  }

  if (opencodeChanged.length > 0) {
    console.log(`\n⚡ [${new Date().toLocaleTimeString()}] OPENCODE SESSION STATE CHANGED! (CHANGED)`);
    for (const s of opencodeChanged) {
      console.log(`   ➜ SessionId: ${s.sessionId} | Status: ${s.status} | Time: ${new Date(s.lastActivity).toLocaleTimeString()}`);
    }
  }

  if (opencodeRemoved.length > 0) {
    console.log(`\n🗑️ [${new Date().toLocaleTimeString()}] OPENCODE SESSION REMOVED! (REMOVED)`);
    for (const s of opencodeRemoved) {
      console.log(`   ➜ SessionId: ${s.sessionId}`);
    }
  }
};

// Start watching every 1 second
startWatcher(onChange, 1000);

// Run for 60 seconds
let remaining = 60;
const timer = setInterval(() => {
  remaining -= 10;
  if (remaining > 0) {
    console.log(`[Heartbeat] Watcher active... (${remaining}s remaining)`);
  } else {
    clearInterval(timer);
    stopWatcher(onChange);
    console.log("\n=================================================");
    console.log(`[Finished] 60-second live watcher complete at ${new Date().toLocaleTimeString()}`);
    console.log("=================================================");
    process.exit(0);
  }
}, 10000);
