const WebSocket = require("ws");
const readline = require("readline");

const SERVER_URL = process.argv[2] || "ws://localhost:6767";

const ws = new WebSocket(SERVER_URL);

let currentSession = null;
let agentName = "";

// terminal colors
const C = {
  reset: "\x1b[0m",
  bold: "\x1b[1m",
  dim: "\x1b[2m",
  green: "\x1b[32m",
  cyan: "\x1b[36m",
  yellow: "\x1b[33m",
  red: "\x1b[31m",
  magenta: "\x1b[35m",
  blue: "\x1b[34m",
  bg: "\x1b[48;5;236m",
};

ws.on("open", () => {
  console.log(`${C.green}${C.bold}connected${C.reset} to ${SERVER_URL}\n`);
  promptInput();
});

ws.on("message", (raw) => {
  const msg = JSON.parse(raw.toString());

  if (msg.type === "session_started") {
    currentSession = msg.sessionId;
    agentName = msg.agent;
    console.log(
      `\n${C.cyan}${C.bold}● ${msg.agent} started${C.reset} ${C.dim}(session: ${msg.sessionId})${C.reset}\n`
    );
  } else if (msg.type === "agent_event") {
    renderEvent(msg.event);
  } else if (msg.type === "agent_text") {
    console.log(`${C.dim}${msg.text}${C.reset}`);
  } else if (msg.type === "agent_stderr") {
    console.log(`${C.red}${C.dim}${msg.text}${C.reset}`);
  } else if (msg.type === "session_ended") {
    console.log(
      `\n${C.yellow}● session ended${C.reset} ${C.dim}(exit: ${msg.exitCode})${C.reset}\n`
    );
    currentSession = null;
    promptInput();
  } else if (msg.type === "turn_ended") {
    console.log(
      `\n${C.cyan}● turn ended${C.reset} ${C.dim}(${msg.stopReason})${C.reset}\n`
    );
    promptInput();
  } else if (msg.type === "session_cancelled") {
    console.log(`\n${C.yellow}● session cancelled${C.reset}\n`);
    currentSession = null;
    promptInput();
  } else if (msg.type === "error") {
    console.log(`${C.red}error: ${msg.text}${C.reset}`);
    promptInput();
  }
});

ws.on("close", () => {
  console.log(`\n${C.red}disconnected${C.reset}`);
  process.exit(0);
});

ws.on("error", (err) => {
  console.log(`${C.red}connection error: ${err.message}${C.reset}`);
  process.exit(1);
});

// ── render agent events ──

function renderEvent(evt) {
  // ACP session/update event (has sessionUpdate field)
  if (evt.sessionUpdate) {
    renderAcpUpdate(evt);
    return;
  }

  // Legacy: old JSONL events (opencode/claude/codex)
  const type = evt.type;

  // opencode events
  if (type === "step_start") {
    // new turn starting
  } else if (type === "text") {
    // assistant text output
    const text = evt.part?.text || "";
    if (text) {
      process.stdout.write(`${C.reset}${text}`);
    }
  } else if (type === "step_finish") {
    const tokens = evt.part?.tokens;
    if (tokens) {
      console.log(
        `${C.reset}\n${C.dim}─── ${tokens.input}↑ ${tokens.output}↓ ${tokens.reasoning || 0}think ───${C.reset}`
      );
    }
  }
  // claude events
  else if (type === "assistant") {
    const text = evt.message?.content?.[0]?.text || "";
    if (text) process.stdout.write(`${C.reset}${text}`);
  } else if (type === "result") {
    console.log(`${C.reset}`);
  } else if (type === "tool_use") {
    const name = evt.name || "tool";
    console.log(`${C.magenta}${C.bold}⟡ ${name}${C.reset} ${C.dim}${JSON.stringify(evt.input || {}).slice(0, 80)}${C.reset}`);
  } else if (type === "tool_result") {
    const content = evt.content?.[0]?.text || "";
    const preview = content.slice(0, 120).replace(/\n/g, " ");
    console.log(`${C.dim}  ↳ ${preview}${content.length > 120 ? "..." : ""}${C.reset}`);
  }
  // codex events
  else if (type === "thread.started") {
    // thread started
  } else if (type === "turn.started") {
    // turn started
  } else if (type === "message") {
    const role = evt.role || "";
    const text = evt.content?.[0]?.text || "";
    if (role === "assistant" && text) {
      process.stdout.write(`${C.reset}${text}`);
    }
  }
  // system/init events - skip
  else if (type === "system" || type === "init") {
    // skip verbose system info
  }
  // unknown - show type only
  else {
    // skip other noisy events
  }
}

function renderAcpUpdate(update) {
  const type = update.sessionUpdate;

  if (type === "agent_message_chunk") {
    const text = update.content?.text || "";
    if (text) process.stdout.write(`${C.reset}${text}`);
  }
  else if (type === "tool_call") {
    const title = update.title || "tool";
    const kind = update.kind || "unknown";
    console.log(`${C.magenta}${C.bold}⟡ ${title}${C.reset} ${C.dim}(${kind})${C.reset}`);
    if (update.toolCallId) console.log(`${C.dim}  id: ${update.toolCallId}${C.reset}`);
  }
  else if (type === "tool_call_update") {
    const status = update.status || "unknown";
    const preview = update.content?.[0]?.content?.text?.slice(0, 120) || "";
    console.log(`${C.dim}  ↳ ${status}${preview ? ": " + preview.replace(/\n/g, " ") : ""}${C.reset}`);
  }
  else if (type === "plan") {
    const entries = update.entries || [];
    console.log(`${C.dim}─── Plan ───${C.reset}`);
    for (const entry of entries) {
      const icon = entry.status === "completed" ? "✓" : entry.status === "in_progress" ? "◎" : "○";
      console.log(`${C.blue}  ${icon} ${entry.content}${C.reset}`);
    }
  }
  else if (type === "user_message_chunk") {
    // user message echoed back - skip
  }
  else if (type === "agent_thought_chunk") {
    // skip thought in normal output
  }
  else {
    // unknown ACP update type - skip
  }
}

// ── input handling ──

function promptInput() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  const label = currentSession
    ? `${C.green}${agentName}${C.reset} ${C.bold}›${C.reset} `
    : `${C.bold}›${C.reset} `;

  rl.question(label, (answer) => {
    rl.close();
    const trimmed = answer.trim();
    if (!trimmed) {
      promptInput();
      return;
    }

    // commands
    if (trimmed === "/quit" || trimmed === "/q") {
      ws.close();
      return;
    }
    if (trimmed === "/cancel") {
      if (currentSession) {
        ws.send(JSON.stringify({ type: "cancel", sessionId: currentSession }));
      }
      promptInput();
      return;
    }
    if (trimmed.startsWith("/model ")) {
      // store model preference for next start
      globalThis._modelPref = trimmed.slice(7);
      console.log(`${C.dim}model set to: ${globalThis._modelPref}${C.reset}`);
      promptInput();
      return;
    }

    // if no active session, start a new one
    if (!currentSession) {
      // parse: [agent] [prompt]
      // default agent is opencode
      let agent = "opencode";
      let prompt = trimmed;
      let model = globalThis._modelPref || undefined;

      if (trimmed.startsWith("claude ")) {
        agent = "claude";
        prompt = trimmed.slice(7);
      } else if (trimmed.startsWith("codex ")) {
        agent = "codex";
        prompt = trimmed.slice(6);
      } else if (trimmed === "claude" || trimmed === "codex" || trimmed === "opencode") {
        agent = trimmed;
        prompt = undefined;
      }

      ws.send(
        JSON.stringify({
          type: "start",
          agent,
          prompt,
          model,
          cwd: process.cwd(),
        })
      );
      // session_started will trigger promptInput() when ready
    } else {
      // send input to running session
      ws.send(
        JSON.stringify({ type: "input", sessionId: currentSession, text: trimmed })
      );
      // turn_ended will trigger promptInput() when the turn ends
    }
  });
}

// handle ctrl+c
process.on("SIGINT", () => {
  if (currentSession) {
    ws.send(JSON.stringify({ type: "cancel", sessionId: currentSession }));
    // turn_ended or session_ended will trigger promptInput()
    setTimeout(promptInput, 200);
  } else {
    ws.close();
  }
});
