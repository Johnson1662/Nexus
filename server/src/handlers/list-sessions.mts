import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { isValidAgent } from "../discovery/agents.mjs";
import { scanLocalSessionStatuses, mergeSessionStatus } from "../discovery/session-watcher.mjs";
import { agentRegistry } from "../agent-registry-service.mjs";
import { applyTitles } from "../session-titles.mjs";
import { resolveWorkspacePath, isWorkspacePathWithin } from "../path-utils.mjs";
import { HerdrAdapter } from "../discovery/herdr-adapter.mjs";
import { listAmbientSessions } from "../discovery/ambient-session.mjs";
import path from "node:path";

const herdrSessionTimes = new Map<string, { createdAt: number; lastActivity: number; status: string }>();

function getHerdrTimes(paneId: string, status: string, createdAt?: number, lastActivity?: number) {
  const now = Date.now();
  const previous = herdrSessionTimes.get(paneId);
  const times = {
    createdAt: createdAt || previous?.createdAt || now,
    lastActivity: lastActivity || (previous?.status !== status ? now : previous?.lastActivity) || now,
    status,
  };
  herdrSessionTimes.set(paneId, times);
  return times;
}

export async function handleListSessions(
  ws: WebSocket,
  cwd?: string,
  agent?: string,
  useHerdr?: boolean,
  requestId?: string,
): Promise<void> {
  const resolvedCwd = resolveWorkspacePath(cwd);
  // 如果启用 Herdr 作为专属后端，则只返回 Herdr 分屏，彻底与 ACP 会话隔离
  if (useHerdr === true) {
    if (!HerdrAdapter.isAvailable()) {
      ws.send(JSON.stringify({
        type: "session_list",
        sessions: [],
        error: "HERDR_NOT_AVAILABLE",
        requestId,
      }));
      return;
    }
    const herdrSessions: any[] = [];
    try {
      const herdrAgents = await HerdrAdapter.listAgentsStrict();
      for (const ha of herdrAgents) {
        if (agent && ha.agent !== agent) continue;
        const haCwd = ha.foreground_cwd || ha.cwd;
        if (resolvedCwd && haCwd) {
          if (!isWorkspacePathWithin(resolvedCwd, haCwd)) continue;
        }
        const resolved = await HerdrAdapter.resolveSessionFile(ha.pane_id);
        const status = ha.agent_status === "working" ? "running" : (ha.agent_status === "blocked" ? "waiting_input" : "idle");
        const times = getHerdrTimes(ha.pane_id, status, resolved?.createdAt, resolved?.lastActivity);
        herdrSessions.push({
          sessionId: `herdr:${ha.pane_id}`,
          title: resolved?.title || ha.terminal_title_stripped || ha.terminal_title || `${ha.agent} (${ha.pane_id})`,
          agent: resolved?.agent || ha.agent,
          cwd: haCwd,
          status,
          source: "herdr",
          lastActivity: times.lastActivity,
          createdAt: times.createdAt,
        });
      }
      ws.send(JSON.stringify({ type: "session_list", sessions: herdrSessions, requestId }));
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.log(`[list-sessions] failed to list herdr agents: ${message}`);
      ws.send(JSON.stringify({
        type: "session_list",
        sessions: [],
        error: message,
        requestId,
      }));
    }
    return;
  }

  const sess = sessionManager.findSessionForWs(ws);
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
        ws.send(JSON.stringify({ type: "session_list", sessions: [], requestId }));
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
  if (useHerdr !== false && HerdrAdapter.isAvailable()) {
    try {
      const herdrAgents = await HerdrAdapter.listAgentsStrict();
      for (const ha of herdrAgents) {
        if (agent && ha.agent !== agent) continue;
        const haCwd = ha.foreground_cwd || ha.cwd;
        if (resolvedCwd && haCwd) {
          if (!isWorkspacePathWithin(resolvedCwd, haCwd)) continue;
        }

        const resolved = await HerdrAdapter.resolveSessionFile(ha.pane_id);
        const resolvedSessionId = resolved?.sessionId;
        const title = resolved?.title || ha.terminal_title_stripped || ha.terminal_title || `${ha.agent} (${ha.pane_id})`;
        const status = ha.agent_status === "working" ? "running" : (ha.agent_status === "blocked" ? "waiting_input" : "idle");
        const times = getHerdrTimes(ha.pane_id, status, resolved?.createdAt, resolved?.lastActivity);

        const existingIdx = sessions.findIndex((s) => s.sessionId === resolvedSessionId || s.sessionId === `herdr:${ha.pane_id}`);
        if (existingIdx >= 0) {
          const existing = sessions.splice(existingIdx, 1)[0];
          sessions.unshift({
            ...existing,
            sessionId: `herdr:${ha.pane_id}`,
            title: title || existing.title,
            cwd: haCwd || existing.cwd,
            status,
            source: "herdr",
            lastActivity: times.lastActivity,
          });
        } else {
          sessions.unshift({
            sessionId: `herdr:${ha.pane_id}`,
            title,
            agent: resolved?.agent || ha.agent,
            cwd: haCwd,
            status,
            source: "herdr",
            lastActivity: times.lastActivity,
            createdAt: times.createdAt,
          });
        }
      }
    } catch (err) {
      console.log(`[list-sessions] failed to merge herdr agents: ${err}`);
    }
  }

  // When useHerdr === false, strictly filter out any sessions currently active in Herdr panes
  if (useHerdr === false && HerdrAdapter.isAvailable()) {
    try {
      const herdrAgents = await HerdrAdapter.listAgentsStrict();
      const herdrSessionIds = new Set<string>();
      for (const ha of herdrAgents) {
        const resolved = await HerdrAdapter.resolveSessionFile(ha.pane_id);
        if (resolved?.sessionId) {
          herdrSessionIds.add(resolved.sessionId);
        }
        herdrSessionIds.add(`herdr:${ha.pane_id}`);
      }
      sessions = sessions.filter(
        (s) => !herdrSessionIds.has(s.sessionId) && s.source !== "herdr",
      );
    } catch (err) {
      console.log(`[list-sessions] failed to filter out herdr agents: ${err}`);
    }
  }

  // Merge ambient sessions (when not in exclusive Herdr mode)
  {
    try {
      const ambientList = listAmbientSessions();
      for (const amb of ambientList) {
        if (agent && amb.agent !== agent) continue;
        if (resolvedCwd && amb.cwd) {
          if (!isWorkspacePathWithin(resolvedCwd, amb.cwd)) continue;
        }
        const existingIdx = sessions.findIndex(
          (s) => s.sessionId === amb.realSessionId || s.sessionId === amb.sessionId,
        );
        if (existingIdx >= 0) {
          sessions.splice(existingIdx, 1);
        }
        sessions.unshift({
          sessionId: amb.sessionId,
          title: `OMP (${path.basename(amb.cwd)})`,
          agent: amb.agent,
          cwd: amb.cwd,
          status: amb.status,
          source: "ambient",
          lastActivity: amb.updatedAt,
          createdAt: amb.updatedAt,
        });
      }
    } catch (err) {
      console.log(`[list-sessions] failed to merge ambient sessions: ${err}`);
    }
  }

  ws.send(JSON.stringify({ type: "session_list", sessions, requestId }));
}
