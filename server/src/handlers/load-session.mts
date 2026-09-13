import type { WebSocket } from "ws";
import fs from "node:fs";
import { sessionManager } from "../session-manager.mjs";
import { HerdrAdapter, HerdrStreamer, findSessionFileById } from "../discovery/herdr-adapter.mjs";
import { readSessionJsonlRecentTurn, readSessionJsonlFullHistory } from "../discovery/herdr-acp-converter.mjs";
import { HerdrTailerRegistry } from "../discovery/herdr-session-tailer.mjs";
import { getAmbientSession } from "../discovery/ambient-session.mjs";
import { getAgentCapabilities } from "../registry/registry.mjs";

// history_full 是单条 WS 消息下发全量事件：22MB 会话可膨胀到 7MB+ JSON，
// 手机端解码卡顿且 6000+ 卡片直接撑爆 ListView。只下发尾部有限事件。
export const MAX_HISTORY_EVENTS = 300;
const MAX_HISTORY_TEXT = 4000;
const historySources = new Map<string, { path: string; minTimestampMs?: number }>();

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

export function extractModelFromSessionFile(filePath?: string): string | undefined {
  if (!filePath) return undefined;
  try {
    if (!fs.existsSync(filePath)) return undefined;
    const stat = fs.statSync(filePath);
    const readSize = Math.min(stat.size, 128 * 1024);
    const buffer = Buffer.alloc(readSize);
    const fd = fs.openSync(filePath, "r");
    fs.readSync(fd, buffer, 0, readSize, Math.max(0, stat.size - readSize));
    fs.closeSync(fd);

    const chunk = buffer.toString("utf8");
    const lines = chunk.split("\n");
    // Scan backwards from newest records
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (!line) continue;
      try {
        const obj = JSON.parse(line);
        if (obj.model && typeof obj.model === "string") return obj.model;
        if (obj.message?.model && typeof obj.message.model === "string") return obj.message.model;
        if (obj.payload?.model && typeof obj.payload.model === "string") return obj.payload.model;
        if (obj.type === "model_change" && typeof obj.model === "string") return obj.model;
      } catch {}
    }
  } catch {}
  return undefined;
}

export function limitHistoryEvents(events: unknown[], before = events.length): {
  events: unknown[]; truncated: boolean; total: number; offset: number; hasMore: boolean;
} {
  const total = events.length;
  const end = Math.max(0, Math.min(before, total));
  let offset = Math.max(0, end - MAX_HISTORY_EVENTS);
  if (before < total) {
    let search = offset;
    while (search > 0 && offset - search < 50) {
      const event = events[search] as { sessionUpdate?: string } | undefined;
      if (event?.sessionUpdate === "user_message_chunk") {
        offset = search;
        break;
      }
      search -= 1;
    }
  }
  return {
    events: events.slice(offset, end).map((e) => truncateHistoryText(e)),
    truncated: offset > 0,
    total,
    offset,
    hasMore: offset > 0,
  };
}

export async function handleLoadHistoryPage(
  ws: WebSocket,
  params: { sessionId?: string; before?: number },
): Promise<void> {
  const sessionId = params.sessionId || "";
  if (!sessionId) return;
  let source = historySources.get(sessionId);
  if (!source && sessionId.startsWith("ambient:")) {
    const ambient = getAmbientSession(sessionId);
    if (ambient) source = { path: ambient.transcriptPath };
  } else if (!source && sessionId.startsWith("herdr:")) {
    const resolved = await HerdrAdapter.resolveSessionFile(sessionId);
    if (resolved?.sessionPath) source = { path: resolved.sessionPath };
  } else if (!source) {
    const path = findSessionFileById(sessionId);
    if (path) source = { path };
  }
  if (!source) {
    try { ws.send(JSON.stringify({ type: "error", sessionId, text: "history source unavailable" })); } catch {}
    return;
  }

  const events = await readSessionJsonlFullHistory(source.path, source.minTimestampMs);
  const page = limitHistoryEvents(events as unknown[], params.before);
  try {
    ws.send(JSON.stringify({
      type: "history_page",
      sessionId,
      events: page.events,
      historyTruncated: page.truncated,
      historyTotal: page.total,
      historyOffset: page.offset,
      historyHasMore: page.hasMore,
    }));
  } catch {}
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
  const { sessionId: targetSessionId, cwd, agent = "omp", model, lastMessageId, freshAt } = params;

  if (!targetSessionId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId is required" })); } catch {}
    return;
  }

  if (targetSessionId.startsWith("ambient:")) {
    const amb = getAmbientSession(targetSessionId);
    if (!amb) {
      try {
        ws.send(JSON.stringify({ type: "error", sessionId: targetSessionId, text: "ambient session not found or stale" }));
      } catch {}
      return;
    }

    const realModel = extractModelFromSessionFile(amb.transcriptPath) || model;
    historySources.set(targetSessionId, { path: amb.transcriptPath });
    try {
      ws.send(JSON.stringify({
        type: "session_started",
        sessionId: targetSessionId,
        agent: amb.agent,
        model: realModel,
        resumed: true,
        source: "ambient",
        streamMode: "acp",
      }));
    } catch { return; }

    // Stage 1: Send only the latest conversation turn for instant opening (<5ms)
    try {
      const events = await readSessionJsonlRecentTurn(amb.transcriptPath);
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

    // Attach live tailer and derive turn completion from the ambient claim.
    const tailer = HerdrTailerRegistry.getOrCreate(
      amb.transcriptPath,
      targetSessionId,
      "ambient",
      undefined,
      true,
    );
    tailer.subscribe(ws);
    if (amb.status === "running") tailer.markWorking();
    ws.on("close", () => {
      tailer.unsubscribe(ws);
    });

    // Stage 2: Asynchronously load full history in background
    setTimeout(async () => {
      if (ws.readyState !== 1 /* OPEN */) return;
      try {
        const fullEvents = await readSessionJsonlFullHistory(amb.transcriptPath);
        const limited = limitHistoryEvents(fullEvents as unknown[]);
        ws.send(JSON.stringify({
          type: "history_full",
          sessionId: targetSessionId,
          events: limited.events,
          historyTruncated: limited.truncated,
          historyTotal: limited.total,
          historyOffset: limited.offset,
          historyHasMore: limited.hasMore,
        }));
      } catch (err) {
        console.error(`[load-session] Error loading full history for ${targetSessionId}:`, err);
      }
    }, 350);

    return;
  }

  if (targetSessionId.startsWith("herdr:")) {
    const paneId = targetSessionId.slice("herdr:".length);
    const resolved = await HerdrAdapter.resolveSessionFile(paneId);
    const resolvedAgent = resolved?.agent || agent;

    const enterTerminalMode = async () => {
      const initialText = await HerdrAdapter.readTerminal(paneId, 100, "text");
      try {
        ws.send(JSON.stringify({
          type: "session_started",
          sessionId: targetSessionId,
          agent: resolvedAgent,
          model,
          resumed: true,
          source: "herdr",
          streamMode: "terminal",
        }));
        if (initialText) {
          ws.send(JSON.stringify({
            type: "agent_event",
            sessionId: targetSessionId,
            event: {
              sessionUpdate: "agent_message_chunk",
              content: { type: "text", text: initialText },
            },
          }));
        }
      } catch { return; }

      HerdrStreamer.seedContent(paneId, initialText);
      const listener = (msg: unknown) => {
        try { ws.send(JSON.stringify(msg)); }
        catch { HerdrStreamer.unsubscribe(paneId, listener); }
      };
      HerdrStreamer.subscribe(paneId, listener);
      ws.on("close", () => HerdrStreamer.unsubscribe(paneId, listener));
    };

    if (getAgentCapabilities(resolvedAgent)?.structuredHistory !== true) {
      await enterTerminalMode();
      return;
    }

    // 1. Structured ACP mode using session.jsonl (also used for terminal→ACP upgrade)
    const enterAcpMode = async (
      r: NonNullable<Awaited<ReturnType<typeof HerdrAdapter.resolveSessionFile>>>,
      minTimestampMs?: number,
    ) => {
      historySources.set(targetSessionId, { path: r.sessionPath!, minTimestampMs });
      const realModel = extractModelFromSessionFile(r.sessionPath) || model;
      try {
        ws.send(JSON.stringify({
          type: "session_started",
          sessionId: targetSessionId,
          agent: r.agent || agent,
          model: realModel,
          resumed: true,
          source: "herdr",
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
            historyOffset: limited.offset,
            historyHasMore: limited.hasMore,
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
          source: "herdr",
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
    await enterTerminalMode();
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
          HerdrStreamer.stop(paneId);
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
    historySources.set(targetSessionId, { path: diskFile });
    const realModel = extractModelFromSessionFile(diskFile) || model;
    try {
      ws.send(JSON.stringify({
        type: "session_started",
        sessionId: targetSessionId,
        agent,
        model: realModel,
        resumed: true,
        streamMode: "acp",
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
          historyOffset: limited.offset,
          historyHasMore: limited.hasMore,
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
      authMethods: sess.client.authMethods,
      configOptions: sess.client.configOptions,
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
