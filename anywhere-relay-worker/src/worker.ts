// ── Types ──────────────────────────────────────────────────────────────────

type Role = "host" | "client";

interface Env {
  RELAY: DurableObjectNamespace;
}

interface ClientEntry {
  ws: WebSocket;
  hostId: string;
  key: string;
}

// ── Constants ──────────────────────────────────────────────────────────────

const MAX_PENDING_FRAMES = 200;

// ── Durable Object ─────────────────────────────────────────────────────────
//
// IMPORTANT: We use plain ws.accept() + class fields, NOT state.acceptWebSocket().
// The hibernation API (acceptWebSocket) serializes the DO instance, resetting
// all class fields on wake-up.  By using ws.accept() instead, the DO stays
// in memory as long as at least one WebSocket is open (holds a reference via
// the alarm/event loop).  Class fields (hostWs, clients) remain valid.

export class RelayDurableObject {
  private state: DurableObjectState;
  private env: Env;

  // In-memory state — valid while DO is alive
  private hostWs: WebSocket | null = null;
  private hostDeviceId: string | null = null;
  private clients: Map<string, ClientEntry> = new Map();

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const role = url.searchParams.get("role") as Role | null;
    const deviceId = url.searchParams.get("deviceId")?.trim();
    const targetHostId = url.searchParams.get("targetHostId")?.trim();

    if (!role || (role !== "host" && role !== "client")) {
      return new Response("Invalid role", { status: 400 });
    }

    const pair = new WebSocketPair();
    const [server, client] = Object.values(pair);

    // Use manual accept() — prevents DO hibernation while WS is open
    server.accept();

    if (role === "host") {
      if (!deviceId) return new Response("Missing deviceId", { status: 400 });
      this.handleHostConnect(server, deviceId);
    } else {
      if (!targetHostId) return new Response("Missing targetHostId", { status: 400 });
      this.handleClientConnect(server, targetHostId);
    }

    return new Response(null, { status: 101, webSocket: client });
  }

  // ── Host ──────────────────────────────────────────────────────────────

  private handleHostConnect(ws: WebSocket, deviceId: string): void {
    if (this.hostWs) {
      try { this.hostWs.close(1008, "Replaced"); } catch { }
    }
    this.hostWs = ws;
    this.hostDeviceId = deviceId;

    ws.addEventListener("message", (event: MessageEvent) => {
      const data = typeof event.data === "string"
        ? event.data
        : new TextDecoder().decode(event.data as ArrayBuffer);
      // Host → broadcast to all clients
      for (const [, entry] of this.clients) {
        try { entry.ws.send(data); } catch { this.clients.delete(entry.key); }
      }
    });

    ws.addEventListener("close", () => {
      if (this.hostWs === ws) { this.hostWs = null; this.hostDeviceId = null; }
    });

    ws.addEventListener("error", () => {
      if (this.hostWs === ws) { this.hostWs = null; this.hostDeviceId = null; }
    });

    // Flush buffered frames
    this.flushPendingForHost(ws);
  }

  // ── Client ────────────────────────────────────────────────────────────

  private handleClientConnect(ws: WebSocket, hostId: string): void {
    const key = crypto.randomUUID();
    this.clients.set(key, { ws, hostId, key });

    ws.addEventListener("message", (event: MessageEvent) => {
      const data = typeof event.data === "string"
        ? event.data
        : new TextDecoder().decode(event.data as ArrayBuffer);

      if (this.hostWs) {
        try { this.hostWs.send(data); } catch {
          this.hostWs = null;
          this.hostDeviceId = null;
        }
      }
    });

    ws.addEventListener("close", () => {
      this.clients.delete(key);
      this.sendToHost(JSON.stringify({ type: "relay_client_disconnected", hostId, clientKey: key }));
    });

    ws.addEventListener("error", () => {
      this.clients.delete(key);
      this.sendToHost(JSON.stringify({ type: "relay_client_disconnected", hostId, clientKey: key }));
    });

    // Notify host
    this.sendToHost(JSON.stringify({ type: "relay_client_connected", hostId, clientKey: key }));
  }

  // ── Internal ──────────────────────────────────────────────────────────

  private sendToHost(data: string): void {
    if (this.hostWs) {
      try { this.hostWs.send(data); } catch { this.hostWs = null; this.hostDeviceId = null; }
    }
  }

  private async flushPendingForHost(hostWs: WebSocket): Promise<void> {
    try {
      const entries = await this.state.storage.list({ prefix: "buf:" });
      for (const [bufKey, frames] of entries) {
        if (!Array.isArray(frames)) continue;
        for (const frame of frames) {
          try { hostWs.send(frame); } catch { return; }
        }
        await this.state.storage.delete(bufKey);
      }
    } catch { /* storage error */ }
  }
}

// ── Worker Entry ────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/ws") {
      return new Response("Use /ws", { status: 404 });
    }
    const upgrade = request.headers.get("Upgrade") || "";
    if (!upgrade.toLowerCase().includes("websocket")) {
      return new Response("WS required", { status: 426 });
    }

    const role = url.searchParams.get("role");
    const deviceId = url.searchParams.get("deviceId")?.trim();
    const targetHostId = url.searchParams.get("targetHostId")?.trim();

    if (!role) return new Response("Missing role", { status: 400 });
    const hostId = role === "host" ? deviceId : targetHostId;
    if (!hostId) return new Response("Missing hostId", { status: 400 });

    const doId = env.RELAY.idFromName(`relay:${hostId}`);
    return env.RELAY.get(doId).fetch(request);
  },
};
