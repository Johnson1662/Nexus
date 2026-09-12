import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { HerdrAdapter, HerdrStreamer, findSessionFileById } from "../discovery/herdr-adapter.mjs";
import { readSessionJsonlRecentTurn, readSessionJsonlFullHistory } from "../discovery/herdr-acp-converter.mjs";
import { HerdrTailerRegistry } from "../discovery/herdr-session-tailer.mjs";

// history_full 是单条 WS 消息下发全量事件：22MB 会话可膨胀到 7MB+ JSON，
// 手机端解码卡顿且 6000+ 卡片直接撑爆 ListView。只下发尾部有限事件。
export const MAX_HISTORY_EVENTS = 300;
const MAX_HISTORY_TEXT = 4000;

function truncateHistoryText(value: unknown): unknown {
  if (typeof value === "string") {
    return value.length > MAX_HISTORY_TEXT ? value.slice(0, MAX_HISTORY_TEXT) + "…" : value;
  }
  if (Array.isArray(value)) {
    return value.map(truncateHistoryText);
  }
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = k === "text" || k === "content" ? truncateHistoryText(v) : v;
    }
    return out;
  }
  return value;
}

export function limitHistoryEvents(events: unknown[]): { events: unknown[]; truncated: boolean; total: number } {
  const total = events.length;
  if (total <= MAX_HISTORY_EVENTS) {
    return { events: events.map((e) => truncateHistoryText(e)), truncated: false, total };
  }
  return {
    events: events.slice(total - MAX_HISTORY_EVENTS).map((e) => truncateHistoryText(e)),
    truncated: true,
    total,
  };
}

export async function handleLoadSession(
  ws: WebSocket,
  params: {
    sessionId: string;
    cwd?: string;
    agent?: string;
    model?: string;
    lastMessageId?: string;
    freshAt?: number;
  },
): Promise<void> {
  const { sessionId: targetSessionId, cwd, agent = "opencode", model, lastMessageId, freshAt } = params;

  if (!targetSessionId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId is required" })); } catch {}
    return;
  }

  if (targetSessionId.startsWith("herdr:")) {
    const paneId = targetSessionId.slice("herdr:".length);
    const resolved = await HerdrAdapter.resolveSessionFile(paneId);

    // 1. Structured ACP mode using session.jsonl (also used for terminal→ACP upgrade)
    const enterAcpMode = async (
      r: NonNullable<Awaited<ReturnType<typeof HerdrAdapter.resolveSessionFile>>>,
      minTimestampMs?: number,
    ) => {
      try {
        ws.send(JSON.stringify({
          type: "session_started",
          sessionId: targetSessionId,
          agent: r.agent || agent,
          resumed: true,
          streamMode: "acp",
        }));
      } catch { return; }

      // Stage 1: Send only the latest conversation turn for instant opening (<5ms)
      try {
        const events = await readSessionJsonlRecentTurn(r.sessionPath!, minTimestampMs);
        for (const ev of events) {
          ws.send(JSON.stringify({
            type: "agent_event",
            sessionId: targetSessionId,
            event: ev,
          }));
        }
        ws.send(JSON.stringify({
          type: "session_loaded",
          sessionId: targetSessionId,
          stage: "recent",
          hasMoreHistory: minTimestampMs === undefined,
        }));
      } catch (err) {
        console.error(`[load-session] Error replaying recent turn for ${targetSessionId}:`, err);
      }

      // Attach live tailer immediately so real-time events are captured
      const tailer = HerdrTailerRegistry.getOrCreate(
        r.sessionPath!,
        targetSessionId,
        paneId,
      );
      tailer.subscribe(ws);
      if (r.agentStatus === "working") tailer.markWorking();
      ws.on("close", () => {
        tailer.unsubscribe(ws);
      });

      // Stage 2: Asynchronously load full history in background
      setTimeout(async () => {
        if (ws.readyState !== 1 /* OPEN */) return;
        try {
          const fullEvents = await readSessionJsonlFullHistory(r.sessionPath!, minTimestampMs);
          const limited = limitHistoryEvents(fullEvents as unknown[]);
          ws.send(JSON.stringify({
            type: "history_full",
            sessionId: targetSessionId,
            events: limited.events,
            historyTruncated: limited.truncated,
            historyTotal: limited.total,
          }));
        } catch (err) {
          console.error(`[load-session] Error loading full history for ${targetSessionId}:`, err);
        }
      }, 350);

    };

    const freshBoundary = typeof freshAt === "number" && Number.isFinite(freshAt) ? freshAt : null;
    if (freshBoundary !== null) {
      // A newly created pane starts empty. Herdr can briefly report an old
      // session path for the new pane, so replay only records written after
      // the creation boundary rather than trusting the path or file mtime.
      try {
        ws.send(JSON.stringify({
          type: "session_started",
          sessionId: targetSessionId,
          agent: resolved?.agent || agent,
          resumed: true,
          streamMode: "acp",
        }));
        ws.send(JSON.stringify({
          type: "session_loaded",
          sessionId: targetSessionId,
          stage: "recent",
          hasMoreHistory: false,
        }));
      } catch { return; }

      const freshTimer = setInterval(async () => {
        if (ws.readyState !== 1 /* OPEN */) { clearInterval(freshTimer); return; }
        try {
          const r = await HerdrAdapter.resolveSessionFile(paneId);
          if (r?.sessionPath) {
            clearInterval(freshTimer);
            await enterAcpMode(r, freshBoundary);
          }
        } catch { /* retry next tick */ }
      }, 1000);
      ws.on("close", () => {
        clearInterval(freshTimer);
      });
      return;
    }

    if (resolved?.sessionPath) {
      await enterAcpMode(resolved);
      return;
    }

    if (resolved && !resolved.sessionPath) {
      // Agent detected but no session file yet (fresh agent): show EMPTY and
      // wait for its own file. Never terminal-fallback here (raw TUI noise)
      // and never another pane's session. First user input makes the agent
      // write its .jsonl, then the poller below flips this socket to ACP.
      try {
        ws.send(JSON.stringify({
          type: "session_started",
          sessionId: targetSessionId,
          agent: resolved.agent || agent,
          resumed: true,
          streamMode: "acp",
        }));
        ws.send(JSON.stringify({
          type: "session_loaded",
          sessionId: targetSessionId,
          stage: "recent",
          hasMoreHistory: false,
        }));
      } catch { return; }

      const emptyTimer = setInterval(async () => {
        if (ws.readyState !== 1 /* OPEN */) { clearInterval(emptyTimer); return; }
        try {
          const r = await HerdrAdapter.resolveSessionFile(paneId);
          if (r?.sessionPath) {
            clearInterval(emptyTimer);
            await enterAcpMode(r);
          }
        } catch { /* retry next tick */ }
      }, 2000);
      ws.on("close", () => {
        clearInterval(emptyTimer);
      });
      return;
    }

    // 2. Fallback: Raw terminal mode
    const initialText = await HerdrAdapter.readTerminal(paneId, 100, "text");
    try {
      ws.send(JSON.stringify({
        type: "session_started",
        sessionId: targetSessionId,
        agent,
        resumed: true,
        streamMode: "terminal",
      }));
      if (initialText) {
        ws.send(JSON.stringify({
          type: "agent_event",
          sessionId: targetSessionId,
          event: {
            sessionUpdate: "agent_message_chunk",
            content: {
              type: "text",
              text: initialText,
            },
          },
        }));
      }
    } catch { /* WS gone */ }

    HerdrStreamer.seedContent(paneId, initialText);
    const listener = (msg: unknown) => {
      try {
        ws.send(JSON.stringify(msg));
      } catch {
        HerdrStreamer.unsubscribe(paneId, listener);
      }
    };
    HerdrStreamer.subscribe(paneId, listener);
    ws.on("close", () => {
      HerdrStreamer.unsubscribe(paneId, listener);
    });
    // 3. Upgrade: the agent writes its .jsonl seconds after start; when it
    // appears, switch this socket from raw terminal to structured ACP cards.
    let upgradeTries = 0;
    const upgradeTimer = setInterval(async () => {
      if (ws.readyState !== 1 /* OPEN */) { clearInterval(upgradeTimer); return; }
      if (++upgradeTries > 45) { clearInterval(upgradeTimer); return; }
      try {
        const r = await HerdrAdapter.resolveSessionFile(paneId);
        if (r?.sessionPath) {
          clearInterval(upgradeTimer);
          HerdrStreamer.unsubscribe(paneId, listener);
          await enterAcpMode(r);
        }
      } catch { /* retry next tick */ }
    }, 1000);
    ws.on("close", () => {
      clearInterval(upgradeTimer);
    });
    return;
  }

  // Check if targetSessionId matches an existing completed session file on disk
  const diskFile = findSessionFileById(targetSessionId);
  if (diskFile) {
    try {
      ws.send(JSON.stringify({
        type: "session_started",
        sessionId: targetSessionId,
        agent,
        resumed: true,
        streamMode: "acp",
        ...(model ? { model } : {}),
      }));
    } catch { return; }

    try {
      const events = await readSessionJsonlRecentTurn(diskFile);
      for (const ev of events) {
        ws.send(JSON.stringify({
          type: "agent_event",
          sessionId: targetSessionId,
          event: ev,
        }));
      }
      ws.send(JSON.stringify({
        type: "session_loaded",
        sessionId: targetSessionId,
        stage: "recent",
        hasMoreHistory: true,
      }));
    } catch (err) {
      console.error(`[load-session] Error replaying recent turn for disk file ${targetSessionId}:`, err);
    }

    setTimeout(async () => {
      if (ws.readyState !== 1 /* OPEN */) return;
      try {
        const fullEvents = await readSessionJsonlFullHistory(diskFile);
        const limited = limitHistoryEvents(fullEvents as unknown[]);
        ws.send(JSON.stringify({
          type: "history_full",
          sessionId: targetSessionId,
          events: limited.events,
          historyTruncated: limited.truncated,
          historyTotal: limited.total,
        }));
      } catch (err) {
        console.error(`[load-session] Error loading full history for disk file ${targetSessionId}:`, err);
      }
    }, 350);

    // JSONL is only the fast replay source. Continue below to restore the
    // actual ACP session so later input has a live client.
  }

  let sess;
  try {
    sess = await sessionManager.getOrCreate(ws, {
      agent, cwd, model,
      sessionId: targetSessionId,
      mode: "load",
    });
  } catch (err: unknown) {
    const code = typeof err === "object" && err && "code" in err ? String(err.code) : "SESSION_ACCESS_DENIED";
    const message = err instanceof Error ? err.message : String(err);
    try { ws.send(JSON.stringify({ type: "error", sessionId: targetSessionId, code, text: message })); } catch {}
    return;
  }

  const sessionId = sess.sessionId;
  try {
    ws.send(JSON.stringify({
      type: "session_started",
      sessionId,
      agent,
      resumed: true,
      ...(model ? { model } : {}),
    }));
  } catch { /* WS gone */ }

  // Replay buffered events since lastMessageId
  if (lastMessageId) {
    const syncResult = sessionManager.replayBuffer(sessionId, lastMessageId, ws);
    if (syncResult.entries.length > 0) {
      const safeEntries = syncResult.entries
        .map(e => {
          try {
            const parsed = JSON.parse(e.payload);
            if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null;
            // Replay the complete Nexus protocol envelope. Dropping the
            // outer type/sessionId here turns agent_event into an unscoped ACP
            // update and makes Flutter route replay differently from live data.
            const payload = {
              ...parsed,
              sessionId: parsed.sessionId || sessionId,
              messageId: e.messageId,
            };
            return { messageId: e.messageId, payload, timestamp: e.timestamp };
          } catch {
            return null;
          }
        })
        .filter(Boolean);
      try {
        ws.send(JSON.stringify({
          type: "sync_response",
          sessionId,
          entries: safeEntries,
          overflow: syncResult.overflow,
        }));
      } catch { /* WS gone */ }
    }
  }
}
