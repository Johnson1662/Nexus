import type { WebSocket } from "ws";
import { HerdrAdapter } from "../discovery/herdr-adapter.mjs";

export async function handleListHerdrWorkspaces(ws: WebSocket): Promise<void> {
  if (!HerdrAdapter.isAvailable()) {
    ws.send(JSON.stringify({ type: "herdr_workspaces_list", workspaces: [] }));
    return;
  }

  try {
    const rawList = await HerdrAdapter.listWorkspaces();
    const agents = await HerdrAdapter.listAgents();
    const workspaces = rawList.map((w) => {
      // Find matching panes/agents for this workspace to get real CWD
      const matchedAgent = agents.find((a) => a.workspace_id === w.workspace_id);
      const cwd = matchedAgent?.foreground_cwd || matchedAgent?.cwd || "";
      return {
        workspaceId: w.workspace_id,
        name: w.label || w.workspace_id,
        path: cwd,
        paneCount: w.pane_count ?? 1,
        tabCount: w.tab_count ?? 1,
        agentStatus: w.agent_status ?? "idle",
        focused: Boolean(w.focused),
      };
    });
    ws.send(JSON.stringify({ type: "herdr_workspaces_list", workspaces }));
  } catch (err: any) {
    console.error(`[herdr-actions] failed to list workspaces: ${err.message}`);
    ws.send(JSON.stringify({ type: "herdr_workspaces_list", workspaces: [] }));
  }
}

export async function handleCreateHerdrWorkspace(
  ws: WebSocket,
  payload: { label?: string; cwd?: string },
): Promise<void> {
  if (!HerdrAdapter.isAvailable()) {
    ws.send(
      JSON.stringify({
        type: "create_herdr_workspace_done",
        ok: false,
        error: "Herdr is not running on this host",
      }),
    );
    return;
  }

  try {
    const workspaceId = await HerdrAdapter.createWorkspace(payload.label, payload.cwd);
    if (!workspaceId) {
      ws.send(
        JSON.stringify({
          type: "create_herdr_workspace_done",
          ok: false,
          error: "Failed to create Herdr workspace",
        }),
      );
      return;
    }

    ws.send(
      JSON.stringify({
        type: "create_herdr_workspace_done",
        ok: true,
        workspaceId,
        label: payload.label || workspaceId,
        cwd: payload.cwd || "",
      }),
    );
    // Broadcast refreshed workspaces list
    handleListHerdrWorkspaces(ws).catch(() => {});
  } catch (err: any) {
    ws.send(
      JSON.stringify({
        type: "create_herdr_workspace_done",
        ok: false,
        error: err.message || String(err),
      }),
    );
  }
}

export interface CreateHerdrAgentPayload {
  workspaceId: string;
  agentKind: string;
  creationMode?: "pane_split" | "new_tab";
  name?: string;
  cwd?: string;
  title?: string;
}

export async function handleCreateHerdrAgent(
  ws: WebSocket,
  payload: CreateHerdrAgentPayload,
): Promise<void> {
  if (!HerdrAdapter.isAvailable()) {
    ws.send(
      JSON.stringify({
        type: "create_herdr_agent_done",
        ok: false,
        error: "Herdr is not running on this host",
        text: "Herdr is not running on this host",
      }),
    );
    return;
  }

  const { workspaceId, agentKind, creationMode = "pane_split", cwd, title } = payload;
  let targetPaneId: string | null = null;

  try {
    if (creationMode === "new_tab") {
      targetPaneId = await HerdrAdapter.createTab({
        workspace_id: workspaceId,
        label: title || agentKind,
        cwd,
      });
      if (!targetPaneId) {
        console.log(`[herdr-actions] tab.create failed, falling back to pane.split`);
        targetPaneId = await HerdrAdapter.splitPane({
          workspace_id: workspaceId,
          direction: "right",
          cwd,
        });
      }
    } else {
      targetPaneId = await HerdrAdapter.splitPane({
        workspace_id: workspaceId,
        direction: "right",
        cwd,
      });
      if (!targetPaneId) {
        console.log(`[herdr-actions] pane.split failed, falling back to tab.create`);
        targetPaneId = await HerdrAdapter.createTab({
          workspace_id: workspaceId,
          label: title || agentKind,
          cwd,
        });
      }
    }

    if (!targetPaneId) {
      ws.send(
        JSON.stringify({
          type: "create_herdr_agent_done",
          ok: false,
          error: "Failed to allocate pane or tab in Herdr workspace",
          text: "Failed to allocate pane or tab in Herdr workspace",
        }),
      );
      return;
    }

    const agentName =
      payload.name ||
      `${agentKind.toLowerCase().replace(/[^a-z0-9_-]/g, "")}_${Date.now().toString(36).slice(-5)}`;
    const freshAt = Date.now();

    const started = await HerdrAdapter.startAgent({
      pane_id: targetPaneId,
      kind: agentKind,
      name: agentName,
    });

    if (!started) {
      ws.send(
        JSON.stringify({
          type: "create_herdr_agent_done",
          ok: false,
          error: `Failed to start agent "${agentKind}" in pane ${targetPaneId}`,
          text: `Failed to start agent "${agentKind}" in pane ${targetPaneId}`,
        }),
      );
      return;
    }

    ws.send(
      JSON.stringify({
        type: "create_herdr_agent_done",
        ok: true,
        sessionId: `herdr:${targetPaneId}`,
        paneId: targetPaneId,
        workspaceId,
        agent: agentKind,
        freshAt,
        title: title || `${agentKind} (${targetPaneId})`,
      }),
    );
  } catch (err: any) {
    console.error(`[herdr-actions] create_herdr_agent error: ${err.message}`);
    // Best-effort: don't leave an empty split/tab behind after a failed start.
    if (targetPaneId) {
      try { await HerdrAdapter.closePane(targetPaneId); } catch {}
    }
    ws.send(
      JSON.stringify({
        type: "create_herdr_agent_done",
        ok: false,
        error: err.message,
        text: err.message,
      }),
    );
  }
}

export async function handleFocusHerdrTarget(
  ws: WebSocket,
  payload: { paneId?: string; workspaceId?: string },
): Promise<void> {
  if (!HerdrAdapter.isAvailable()) {
    ws.send(
      JSON.stringify({
        type: "focus_herdr_target_done",
        ok: false,
        error: "Herdr is not running on this host",
      }),
    );
    return;
  }
  try {
    if (payload.paneId) {
      await HerdrAdapter.focusAgent(payload.paneId.replace(/^herdr:/, ""));
    }
    if (payload.workspaceId) {
      await HerdrAdapter.focusWorkspace(payload.workspaceId);
    }
    ws.send(JSON.stringify({ type: "focus_herdr_target_done", ok: true }));
  } catch (err: any) {
    console.error(`[herdr-actions] focus_herdr_target error: ${err.message}`);
    ws.send(JSON.stringify({ type: "focus_herdr_target_done", ok: false, error: err.message }));
  }
}

export async function handleInteractHerdrBlocked(
  ws: WebSocket,
  payload: { paneId: string; key: string },
): Promise<void> {
  if (!HerdrAdapter.isAvailable()) {
    ws.send(
      JSON.stringify({
        type: "interact_herdr_blocked_done",
        ok: false,
        error: "Herdr is not running on this host",
      }),
    );
    return;
  }
  if (!payload.paneId) {
    ws.send(
      JSON.stringify({
        type: "interact_herdr_blocked_done",
        ok: false,
        error: "Missing paneId",
      }),
    );
    return;
  }
  try {
    const pane = payload.paneId.replace(/^herdr:/, "");
    await HerdrAdapter.sendKeys(pane, [payload.key]);
    ws.send(JSON.stringify({ type: "interact_herdr_blocked_done", ok: true }));
  } catch (err: any) {
    console.error(`[herdr-actions] interact_herdr_blocked error: ${err.message}`);
    ws.send(JSON.stringify({ type: "interact_herdr_blocked_done", ok: false, error: err.message }));
  }
}
