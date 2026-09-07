import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { isValidAgent } from "../discovery/agents.mjs";
import { scanLocalSessionStatuses, mergeSessionStatus } from "../discovery/session-watcher.mjs";
import { agentRegistry } from "../agent-registry-service.mjs";
import { applyTitles } from "../session-titles.mjs";
import { resolveWorkspacePath } from "../path-utils.mjs";
import { HerdrAdapter } from "../discovery/herdr-adapter.mjs";

export async function handleListSessions(
  ws: WebSocket,
  cwd?: string,
  agent?: string,
  useHerdr?: boolean,
): Promise<void> {
  // 如果启用 Herdr 作为专属后端，则只返回 Herdr 分屏，彻底与 ACP 会话隔离
  if (useHerdr === true) {
    const herdrSessions: any[] = [];
    if (HerdrAdapter.isAvailable()) {
      try {
        const herdrAgents = await HerdrAdapter.listAgents();
        for (const ha of herdrAgents) {
          if (agent && ha.agent !== agent) continue;
          const haCwd = ha.foreground_cwd || ha.cwd;
          const resolved = await HerdrAdapter.resolveSessionFile(ha.pane_id);
          herdrSessions.push({
            sessionId: `herdr:${ha.pane_id}`,
            title: resolved?.title || ha.terminal_title_stripped || ha.terminal_title || `${ha.agent} (${ha.pane_id})`,
            agent: resolved?.agent || ha.agent,
            cwd: haCwd,
            status: ha.agent_status === "working" ? "running" : (ha.agent_status === "blocked" ? "waiting_input" : "idle"),
            source: "herdr",
            lastActivity: Date.now(),
            createdAt: Date.now(),
          });
        }
      } catch (err) {
        console.log(`[list-sessions] failed to list herdr agents: ${err}`);
      }
    }
    ws.send(JSON.stringify({ type: "session_list", sessions: herdrSessions }));
    return;
  }

  const sess = sessionManager.findSessionForWs(ws);
  const resolvedCwd = resolveWorkspacePath(cwd);
  let sessions: any[];

  if (agent) {
    if (!isValidAgent(agent)) {
      ws.send(
        JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }),
      );
      return;
    }
    if (sess?.client?.connected && sess.agent === agent) {
      let timeout: ReturnType<typeof setTimeout> | undefined;
      try {
        const result = await Promise.race([
          sess.client.listSessions(resolvedCwd),
          new Promise<never>((_, reject) => {
            timeout = setTimeout(() => reject(new Error("listSessions timeout")), 12000);
          }),
        ]);
        sessions = ((result as any).sessions || []).map((s: any) => ({
          ...s,
          agent,
        }));
      } catch {
        ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
        return;
      } finally {
        clearTimeout(timeout);
      }
    } else {
      sessions = await agentRegistry.queryAggregateSessions(resolvedCwd, agent);
    }
  } else {
    sessions = await agentRegistry.queryAggregateSessions(resolvedCwd);
  }

  // Apply persisted title overrides and local session statuses
  applyTitles(sessions);
  const localStatuses = await scanLocalSessionStatuses();
  // Filter filesystem statuses through canonical session identity so static
  // labels (e.g. "opencode-active") never attach to unrelated ACP session IDs.
  const knownIds = new Set(sessionManager.getAllSessions().keys());
  const activeIds = sessionManager.getActiveSessionIds();
  const canonicalStatuses = mergeSessionStatus(localStatuses, activeIds, knownIds);
  const statusMap = new Map(
    canonicalStatuses.map((ls: any) => [ls.sessionId, ls]),
  );
  for (const s of sessions) {
    const localStatus = statusMap.get(s.sessionId);
    if (localStatus) {
      s.status = localStatus.status;
      s.lastActivity = localStatus.lastActivity;
    } else if (!s.status) {
      s.status = "idle";
    }
    if (!s.createdAt && s.updatedAt) {
      s.createdAt = new Date(s.updatedAt).getTime();
    }
  }

  // Merge live Herdr panes into session list and place at top
  if (HerdrAdapter.isAvailable()) {
    try {
      const herdrAgents = await HerdrAdapter.listAgents();
      for (const ha of herdrAgents) {
        if (agent && ha.agent !== agent) continue;
        const haCwd = ha.foreground_cwd || ha.cwd;
        if (resolvedCwd && haCwd && !haCwd.startsWith(resolvedCwd)) continue;

        const resolved = await HerdrAdapter.resolveSessionFile(ha.pane_id);
        const resolvedSessionId = resolved?.sessionId;
        const title = resolved?.title || ha.terminal_title_stripped || ha.terminal_title || `${ha.agent} (${ha.pane_id})`;
        const status = ha.agent_status === "working" ? "running" : (ha.agent_status === "blocked" ? "waiting_input" : "idle");

        const existingIdx = sessions.findIndex((s) => s.sessionId === resolvedSessionId || s.sessionId === `herdr:${ha.pane_id}`);
        if (existingIdx >= 0) {
          const existing = sessions.splice(existingIdx, 1)[0];
          sessions.unshift({
            ...existing,
            sessionId: `herdr:${ha.pane_id}`,
            title: title || existing.title,
            status,
            source: "herdr",
            lastActivity: Date.now(),
          });
        } else {
          sessions.unshift({
            sessionId: `herdr:${ha.pane_id}`,
            title,
            agent: resolved?.agent || ha.agent,
            cwd: haCwd,
            status,
            source: "herdr",
            lastActivity: Date.now(),
            createdAt: Date.now(),
          });
        }
      }
    } catch (err) {
      console.log(`[list-sessions] failed to merge herdr agents: ${err}`);
    }
  }

  ws.send(JSON.stringify({ type: "session_list", sessions }));
}
