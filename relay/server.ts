import { serve } from "bun";

// In-memory maps
// hosts: hostId -> host WebSocket
// clients: hostId -> Set of client WebSockets bound to this host
const hosts = new Map<string, any>();
const clients = new Map<string, Set<any>>();

const server = serve({
  port: 12138,
  fetch(req, server) {
    const url = new URL(req.url);
    const role = url.searchParams.get("role");
    // For hosts, deviceId is their own hostId. 
    // For clients, targetHostId specifies which host they want to connect to.
    const hostId = role === "host" ? url.searchParams.get("deviceId") : url.searchParams.get("targetHostId");

    if (!role || !hostId) {
      return new Response("Missing role or deviceId/targetHostId", { status: 400 });
    }

    if (role !== "host" && role !== "client") {
      return new Response("Invalid role", { status: 400 });
    }

    const success = server.upgrade(req, {
      data: { role, hostId },
    });

    if (success) {
      return undefined; // Upgraded
    }

    return new Response("WebSocket upgrade failed", { status: 500 });
  },
  websocket: {
    open(ws) {
      const { role, hostId } = ws.data;
      console.log(`[OPEN] ${role} connected. Target/Self hostId: ${hostId}`);
      if (role === "host") {
        if (hosts.has(hostId)) {
          hosts.get(hostId).close(1008, "New host connected");
        }
        hosts.set(hostId, ws);
      } else if (role === "client") {
        let clientSet = clients.get(hostId);
        if (!clientSet) {
          clientSet = new Set();
          clients.set(hostId, clientSet);
        }
        clientSet.add(ws);
      }
    },
    message(ws, message) {
      const { role, hostId } = ws.data;
      console.log(`[MSG] from=${role} target=${hostId} bytes=${typeof message === "string" ? message.length : message.byteLength ?? 0}`);
      
      if (role === "client") {
        const hostWs = hosts.get(hostId);
        if (hostWs) {
          console.log(`[FWD] client -> host ${hostId}`);
          hostWs.send(message);
        } else {
          console.log(`[WARN] No host found for hostId: ${hostId}`);
        }
      } else if (role === "host") {
        const clientSet = clients.get(hostId);
        if (clientSet && clientSet.size > 0) {
          console.log(`[FWD] host -> ${clientSet.size} clients for ${hostId}`);
          for (const clientWs of clientSet) {
            clientWs.send(message);
          }
        }
      }
    },
    close(ws, code, message) {
      const { role, hostId } = ws.data;
      console.log(`[CLOSE] ${role} disconnected: ${hostId} (${code})`);
      if (role === "host" && hosts.get(hostId) === ws) {
        hosts.delete(hostId);
      } else if (role === "client") {
        const clientSet = clients.get(hostId);
        if (clientSet) {
          clientSet.delete(ws);
          if (clientSet.size === 0) {
            clients.delete(hostId);
          }
        }
      }
    },
  },
});

console.log(`Relay server running on ws://0.0.0.0:${server.port}`);
