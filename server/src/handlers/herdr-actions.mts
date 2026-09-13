import type { WebSocket } from "ws";
import { HerdrAdapter } from "../discovery/herdr-adapter.mjs";
import { HerdrCliError } from "../discovery/herdr-cli.mjs";
import { resolveAgentRuntime } from "../agents-store.mjs";

/**
 * Herdr CLI failures map onto a stable protocol error: a missing binary is
 * reported as "not installed" (the actionable case for the user) and every
 * other failure carries the CLI's own message. No business call is gated on a
 * synchronous availability probe.
 */
function herdrErrorCode(err: unknown): string {
  if (err instanceof HerdrCliError && err.code === "HERDR_BIN_NOT_FOUND") return "HERDR_NOT_INSTALLED";
  return err instanceof Error ? err.message : String(err);
}

export async function handleListHerdrWorkspaces(ws: WebSocket): Promise<void> {
  try {
    const rawList = await HerdrAdapter.listWorkspacesStrict();
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
    ws.send(JSON.stringify({ type: "herdr_workspaces_list", workspaces: [], error: herdrErrorCode(err) }));
  }
}

export async function handleCreateHerdrWorkspace(
  ws: WebSocket,
  payload: { label?: string; cwd?: string },
): Promise<void> {
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
        error: herdrErrorCode(err),
      }),
    );
  }
}

export interface CreateHerdrAgentPayload {
  workspaceId: string;
  /** Nexus agent id. The Herdr kind is resolved server-side from the registry. */
  agentId: string;
  creationMode?: "pane_split" | "new_tab";
  name?: string;
  cwd?: string;
  title?: string;
}

export async function handleCreateHerdrAgent(
  ws: WebSocket,
  payload: CreateHerdrAgentPayload,
): Promise<void> {
  const { workspaceId, agentId, creationMode = "pane_split", cwd, title } = payload;
  const runtime = resolveAgentRuntime(agentId);
  const kind = runtime?.herdrKind ?? null;
  if (!runtime || !kind) {
    ws.send(
      JSON.stringify({
        type: "create_herdr_agent_done",
        ok: false,
        error: "UNKNOWN_AGENT_KIND",
      }),
    );
    return;
  }

  let targetPaneId: string | null = null;
  /** Close a pane we created but could not start an agent in. */
  const releasePane = async (): Promise<void> => {
    if (!targetPaneId) return;
    try { await HerdrAdapter.closePane(targetPaneId); } catch {}
  };

  /**
   * Allocate a pane for the agent, preferring the requested mode but falling
   * back to the other one. Both a refused call and a thrown failure count as
   * "try the other strategy" — a workspace with no splittable pane, for
   * example, can still be served by a new tab.
   */
  const allocatePane = async (): Promise<string | null> => {
    const trySplit = () => HerdrAdapter.splitPane({
      workspace_id: workspaceId,
      direction: "right",
      cwd,
    });
    const tryTab = () => HerdrAdapter.createTab({
      workspace_id: workspaceId,
      label: title || runtime.displayName,
      cwd,
    });
    const strategies = creationMode === "new_tab"
      ? [["tab.create", tryTab], ["pane.split", trySplit]]
      : [["pane.split", trySplit], ["tab.create", tryTab]];

    let lastError: unknown = null;
    for (const [label, strategy] of strategies as Array<[string, () => Promise<string | null>]>) {
      try {
        const paneId = await strategy();
        if (paneId) return paneId;
        console.log(`[herdr-actions] ${label} returned no pane`);
      } catch (err) {
        lastError = err;
        console.log(`[herdr-actions] ${label} failed: ${String(err)}`);
      }
    }
    if (lastError) console.log(`[herdr-actions] pane allocation exhausted: ${String(lastError)}`);
    return null;
  };

  try {
    targetPaneId = await allocatePane();

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
      `${kind.replace(/[^a-z0-9_-]/g, "")}_${Date.now().toString(36).slice(-5)}`;
    const freshAt = Date.now();

    // startAgent returns true or throws; treat a falsy return as failure too so
    // the pane is never leaked.
    const started = await HerdrAdapter.startAgent({
      pane_id: targetPaneId,
      kind,
      name: agentName,
    });
    if (!started) {
      await releasePane();
      ws.send(
        JSON.stringify({
          type: "create_herdr_agent_done",
          ok: false,
          error: `Failed to start agent "${kind}" in pane ${targetPaneId}`,
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
        agent: agentId,
        kind,
        freshAt,
        title: title || `${runtime.displayName} (${targetPaneId})`,
      }),
    );
  } catch (err: any) {
    console.error(`[herdr-actions] create_herdr_agent error: ${err.message}`);
    // Best-effort: don't leave an empty split/tab behind after a failed start.
    await releasePane();
    ws.send(
      JSON.stringify({
        type: "create_herdr_agent_done",
        ok: false,
        error: herdrErrorCode(err),
      }),
    );
  }
}

export async function handleFocusHerdrTarget(
  ws: WebSocket,
  payload: { paneId?: string; workspaceId?: string },
): Promise<void> {
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
    ws.send(JSON.stringify({ type: "focus_herdr_target_done", ok: false, error: herdrErrorCode(err) }));
  }
}

export async function handleInteractHerdrBlocked(
  ws: WebSocket,
  payload: { paneId: string; key: string; asText?: boolean },
): Promise<void> {
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
    if (payload.asText) {
      // Free-form answer: type it literally, then submit, instead of hoping the
      // text happens to name a key.
      await HerdrAdapter.sendText(pane, payload.key);
      await HerdrAdapter.sendKeys(pane, ["enter"]);
    } else {
      await HerdrAdapter.sendKeys(pane, [payload.key]);
    }
    ws.send(JSON.stringify({ type: "interact_herdr_blocked_done", ok: true }));
  } catch (err: any) {
    console.error(`[herdr-actions] interact_herdr_blocked error: ${err.message}`);
    ws.send(JSON.stringify({ type: "interact_herdr_blocked_done", ok: false, error: herdrErrorCode(err) }));
  }
}

export async function handleListHerdrIntegrations(ws: WebSocket): Promise<void> {
  try {
    const { integrations, parsed } = await HerdrAdapter.listIntegrations();
    const payload: Record<string, unknown> = { type: "herdr_integrations_list", integrations };
    if (!parsed) payload.error = "HERDR_STATUS_UNPARSABLE";
    ws.send(JSON.stringify(payload));
  } catch (err: any) {
    console.error(`[herdr-actions] list integrations error: ${err.message}`);
    ws.send(JSON.stringify({
      type: "herdr_integrations_list",
      integrations: [],
      error: herdrErrorCode(err),
    }));
  }
}

export async function handleInstallHerdrIntegration(
  ws: WebSocket,
  payload: { target?: string },
): Promise<void> {
  const target = payload.target?.trim();
  if (!target) {
    ws.send(JSON.stringify({
      type: "install_herdr_integration_done",
      target: "",
      ok: false,
      error: "Missing target",
    }));
    return;
  }

  try {
    await HerdrAdapter.installIntegration(target);
    const { integrations } = await HerdrAdapter.listIntegrations();
    ws.send(JSON.stringify({
      type: "install_herdr_integration_done",
      target,
      ok: true,
      integration: integrations.find((entry) => entry.target === target) ?? null,
    }));
  } catch (err: any) {
    console.error(`[herdr-actions] install integration error: ${err.message}`);
    ws.send(JSON.stringify({
      type: "install_herdr_integration_done",
      target,
      ok: false,
      error: herdrErrorCode(err),
    }));
  }
}
