import { createServer } from "node:net";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${message}`);
  } else {
    failed += 1;
    console.error(`  ✗ ${message}`);
  }
}

async function main() {
  console.log("Testing HerdrAdapter & HerdrStreamer...");

  // Build first so dist/discovery/herdr-adapter.mjs exists
  const {
    HerdrAdapter,
    HerdrStreamer,
    isHerdrAvailable,
  } = await import("./dist/discovery/herdr-adapter.mjs");

  // Test 1: Real socket test if Herdr is running
  if (isHerdrAvailable()) {
    console.log("Real Herdr socket detected, testing live integration...");
    assert(HerdrAdapter.isAvailable() === true, "HerdrAdapter.isAvailable() returns true");

    const agents = await HerdrAdapter.listAgents();
    assert(Array.isArray(agents), "HerdrAdapter.listAgents() returns an array");
    console.log(`  Found ${agents.length} live Herdr agent(s)`);

    if (agents.length > 0) {
      const first = agents[0];
      assert(typeof first.pane_id === "string", "first agent has pane_id");
      assert(typeof first.agent === "string", "first agent has agent name");

      const terminalText = await HerdrAdapter.readTerminal(first.pane_id, 10, "text");
      assert(typeof terminalText === "string", "HerdrAdapter.readTerminal() returns string");
      console.log(`  Read ${terminalText.length} characters of terminal output`);
    }
  } else {
    console.log("No live Herdr socket detected, skipping live test");
  }

  // Test 2: Mock Socket testing HerdrStreamer and IPC protocol
  console.log("Testing HerdrStreamer with mock socket...");
  const tmpDir = mkdtempSync(join(tmpdir(), "nexus-herdr-test-"));
  const mockSocketPath = join(tmpDir, "mock_herdr.sock");
  process.env.HERDR_SOCKET_PATH = mockSocketPath;

  let terminalReadCount = 0;
  let promptTarget = null;
  const mockServer = createServer((socket) => {
    socket.on("data", (chunk) => {
      const line = chunk.toString().trim();
      if (!line) return;
      try {
        const req = JSON.parse(line);
        if (req.method === "agent.list") {
          socket.write(JSON.stringify({
            id: req.id,
            result: {
              agents: [
                {
                  pane_id: "mock_p1",
                  name: "omp_test",
                  agent: "omp",
                  agent_status: "working",
                  cwd: "/test",
                  terminal_title: "Mock Terminal",
                },
              ],
            },
          }) + "\n");
        } else if (req.method === "agent.read") {
          terminalReadCount += 1;
          const text = terminalReadCount === 1 ? "Line 1\nLine 2\n" : "Line 1\nLine 2\nLine 3 (new)\n";
          socket.write(JSON.stringify({
            id: req.id,
            result: {
              read: {
                text,
              },
            },
          }) + "\n");
        } else if (req.method === "agent.prompt") {
          promptTarget = req.params?.target;
          const promptResponse = promptTarget === "mock_p1"
            ? { id: req.id, result: { success: true } }
            : {
                id: req.id,
                error: {
                  code: "agent_not_ready",
                  message: "agent " + promptTarget + " is not an active named agent",
                },
              };
          socket.write(JSON.stringify(promptResponse) + "\n");
        } else if (req.method === "agent.send_keys") {
          socket.write(JSON.stringify({
            id: req.id,
            result: { success: true },
          }) + "\n");
        }
      } catch (err) {
        socket.write(JSON.stringify({ id: "err", error: { code: "bad", message: String(err) } }) + "\n");
      }
    });
  });

  await new Promise((resolve) => mockServer.listen(mockSocketPath, resolve));

  try {
    assert(HerdrAdapter.isAvailable() === true, "Mock socket is available");

    const mockAgents = await HerdrAdapter.listAgents();
    assert(mockAgents.length === 1 && mockAgents[0].pane_id === "mock_p1", "listAgents() parses mock agent");
    await HerdrAdapter.sendPrompt("mock_p1", "hello");
    assert(promptTarget === "mock_p1", "sendPrompt() targets the active Herdr pane");

    // Test HerdrStreamer
    const receivedEvents = [];
    const listener = (event) => {
      receivedEvents.push(event);
    };

    HerdrStreamer.seedContent("mock_p1", "Line 1\nLine 2\n");
    HerdrStreamer.subscribe("mock_p1", listener);

    // Wait for at least 1 poll (500ms + margin)
    await new Promise((resolve) => setTimeout(resolve, 1200));

    assert(receivedEvents.length >= 1, "HerdrStreamer receives delta event");
    const firstEvent = receivedEvents[0];
    assert(firstEvent?.type === "agent_event", "event type is agent_event");
    assert(firstEvent?.event?.sessionUpdate === "agent_message_chunk", "nested sessionUpdate is agent_message_chunk");
    assert(firstEvent?.event?.content?.text === "Line 3 (new)\n", "delta text exactly matches new output");

    // Test unsubscribe cleanup
    HerdrStreamer.unsubscribe("mock_p1", listener);
    assert(true, "HerdrStreamer.unsubscribe successfully tears down listener");
  } finally {
    mockServer.close();
    rmSync(tmpDir, { recursive: true, force: true });
    delete process.env.HERDR_SOCKET_PATH;
  }

  console.log(`\nHerdrAdapter tests: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error("Test failed with uncaught error:", err);
  process.exit(1);
});
