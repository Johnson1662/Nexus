import { handleListSessions } from "../dist/handlers/list-sessions.mjs";
import { HerdrAdapter } from "../dist/discovery/herdr-adapter.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${message}`);
  } else {
    failed += 1;
    console.error(`  ✗ FAIL: ${message}`);
  }
}

console.log("Testing handleListSessions Herdr filtering...");

const originalIsAvailable = HerdrAdapter.isAvailable;
const originalListAgents = HerdrAdapter.listAgents;
const originalResolveSessionFile = HerdrAdapter.resolveSessionFile;

try {
  HerdrAdapter.isAvailable = () => true;
  HerdrAdapter.listAgents = async () => [
    {
      pane_id: "test_pane_1",
      agent: "omp",
      cwd: "/test",
      agent_status: "idle",
      terminal_title: "Mock Terminal",
    },
  ];
  HerdrAdapter.resolveSessionFile = async () => ({
    sessionId: "mock_herdr_uuid_1234",
    agent: "omp",
    paneId: "test_pane_1",
    title: "Mock Session",
  });

  // Test 1: useHerdr === false -> must NOT include any herdr sessions
  {
    const sent = [];
    const transport = {
      send(message) {
        sent.push(JSON.parse(String(message)));
      },
    };
    await handleListSessions(transport, undefined, undefined, false);
    const sessionListMsg = sent.find((m) => m.type === "session_list");
    assert(sessionListMsg !== undefined, "returns session_list message when useHerdr=false");
    const hasHerdr = (sessionListMsg.sessions || []).some(
      (s) => s.source === "herdr" || s.sessionId.startsWith("herdr:") || s.sessionId === "mock_herdr_uuid_1234",
    );
    assert(!hasHerdr, "useHerdr=false strictly excludes both herdr: panes and raw UUIDs of active Herdr sessions");
  }

  // Test 2: useHerdr === true -> must ONLY include herdr sessions
  {
    const sent = [];
    const transport = {
      send(message) {
        sent.push(JSON.parse(String(message)));
      },
    };
    await handleListSessions(transport, undefined, undefined, true);
    const sessionListMsg = sent.find((m) => m.type === "session_list");
    assert(sessionListMsg !== undefined, "returns session_list message when useHerdr=true");
    const sessions = sessionListMsg.sessions || [];
    assert(sessions.length === 1, "useHerdr=true returns herdr sessions");
    const allHerdr = sessions.every(
      (s) => s.source === "herdr" && s.sessionId.startsWith("herdr:"),
    );
    assert(allHerdr, "useHerdr=true includes ONLY herdr sessions");
  }

  // Test 3: useHerdr === undefined -> merges live herdr sessions (legacy behavior)
  {
    const sent = [];
    const transport = {
      send(message) {
        sent.push(JSON.parse(String(message)));
      },
    };
    await handleListSessions(transport, undefined, undefined, undefined);
    const sessionListMsg = sent.find((m) => m.type === "session_list");
    assert(sessionListMsg !== undefined, "returns session_list message when useHerdr=undefined");
    const hasHerdr = (sessionListMsg.sessions || []).some(
      (s) => s.source === "herdr" || s.sessionId.startsWith("herdr:"),
    );
    assert(hasHerdr, "useHerdr=undefined merges live herdr sessions for backwards compatibility");
  }
} finally {
  HerdrAdapter.isAvailable = originalIsAvailable;
  HerdrAdapter.listAgents = originalListAgents;
  HerdrAdapter.resolveSessionFile = originalResolveSessionFile;
}

console.log(`\nList sessions filtering tests: ${passed} passed, ${failed} failed`);
if (failed > 0) {
  process.exit(1);
}
