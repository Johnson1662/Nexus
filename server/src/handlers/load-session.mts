import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { HerdrAdapter, HerdrStreamer, findSessionFileById } from "../discovery/herdr-adapter.mjs";
import { readSessionJsonlRecentTurn, readSessionJsonlFullHistory } from "../discovery/herdr-acp-converter.mjs";
import { HerdrTailerRegistry } from "../discovery/herdr-session-tailer.mjs";

export async function handleLoadSession(
  ws: WebSocket,
  params: {
    sessionId: string;
    cwd?: string;
    agent?: string;
    model?: string;
    lastMessageId?: string;
  },
): Promise<void> {
  const { sessionId: targetSessionId, cwd, agent = "opencode", model, lastMessageId } = params;

  if (!targetSessionId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId is required" })); } catch {}
    return;
  }

  if (targetSessionId.startsWith("herdr:")) {
    const paneId = targetSessionId.slice("herdr:".length);
    const resolved = await HerdrAdapter.resolveSessionFile(paneId);

    if (resolved?.sessionPath) {
      // 1. Structured ACP mode using session.jsonl
      try {
        ws.send(JSON.stringify({
          type: "session_started",
          sessionId: targetSessionId,
          agent: resolved.agent || agent,
          resumed: true,
          streamMode: "acp",
        }));
      } catch { return; }

      // Stage 1: Send only the latest conversation turn for instant opening (<5ms)
      try {
        const events = await readSessionJsonlRecentTurn(resolved.sessionPath);
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
        console.error(`[load-session] Error replaying recent turn for ${targetSessionId}:`, err);
      }

      // Attach live tailer immediately so real-time events are captured
      const tailer = HerdrTailerRegistry.getOrCreate(
        resolved.sessionPath,
        targetSessionId,
        paneId,
      );
      tailer.subscribe(ws);
      ws.on("close", () => {
        tailer.unsubscribe(ws);
      });

      // Stage 2: Asynchronously load full history in background
      setTimeout(async () => {
        if (ws.readyState !== 1 /* OPEN */) return;
        try {
          const fullEvents = await readSessionJsonlFullHistory(resolved.sessionPath!);
          ws.send(JSON.stringify({
            type: "history_full",
            sessionId: targetSessionId,
            events: fullEvents,
          }));
        } catch (err) {
          console.error(`[load-session] Error loading full history for ${targetSessionId}:`, err);
        }
      }, 350);

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
        ws.send(JSON.stringify({
          type: "history_full",
          sessionId: targetSessionId,
          events: fullEvents,
        }));
      } catch (err) {
        console.error(`[load-session] Error loading full history for disk file ${targetSessionId}:`, err);
      }
    }, 350);

    return;
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
