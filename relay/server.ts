import { serve } from "bun";

// In-memory maps mapping deviceId to the active WebSocket connections
const hosts = new Map<string, any>();
const clients = new Map<string, any>();

const server = serve({
  port: 12138,
  fetch(req, server) {
    const url = new URL(req.url);
    const role = url.searchParams.get("role");
    const deviceId = url.searchParams.get("deviceId");

    if (!role || !deviceId) {
      return new Response("Missing role or deviceId", { status: 400 });
    }

    if (role !== "host" && role !== "client") {
      return new Response("Invalid role", { status: 400 });
    }

    const success = server.upgrade(req, {
      data: { role, deviceId },
    });

    if (success) {
      return undefined; // Upgraded
    }

    return new Response("WebSocket upgrade failed", { status: 500 });
  },
  websocket: {
    open(ws) {
      const { role, deviceId } = ws.data;
      console.log(`[OPEN] ${role} connected: ${deviceId}`);
      if (role === "host") {
        // If an old host was connected, close it to avoid conflicts
        if (hosts.has(deviceId)) {
          hosts.get(deviceId).close(1008, "New host connected");
        }
        hosts.set(deviceId, ws);
      } else if (role === "client") {
        if (clients.has(deviceId)) {
          clients.get(deviceId).close(1008, "New client connected");
        }
        clients.set(deviceId, ws);
      }
    },
    message(ws, message) {
      const { role, deviceId } = ws.data;
      console.log(`[MSG] from=${role} device=${deviceId} bytes=${typeof message === "string" ? message.length : message.byteLength ?? 0}`);
      
      if (role === "client") {
        const hostWs = hosts.get(deviceId);
        if (hostWs) {
          console.log(`[FWD] client -> host ${deviceId}`);
          hostWs.send(message);
        } else {
          console.log(`[WARN] No host found for deviceId: ${deviceId}`);
        }
      } else if (role === "host") {
        const clientWs = clients.get(deviceId);
        if (clientWs) {
          console.log(`[FWD] host -> client ${deviceId}`);
          clientWs.send(message);
        }
      }
    },
    close(ws, code, message) {
      const { role, deviceId } = ws.data;
      console.log(`[CLOSE] ${role} disconnected: ${deviceId} (${code})`);
      if (role === "host" && hosts.get(deviceId) === ws) {
        hosts.delete(deviceId);
      } else if (role === "client" && clients.get(deviceId) === ws) {
        clients.delete(deviceId);
      }
    },
  },
});

console.log(`Relay server running on ws://0.0.0.0:${server.port}`);
