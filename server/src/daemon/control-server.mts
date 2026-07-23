import http, { type IncomingMessage, type ServerResponse } from "node:http";

// ── Interfaces ─────────────────────────────────────────────────

export interface DaemonStatus {
  pid: number;
  port: number;
  uptime: number;
  activeSessions: number;
}

export interface ControlServerOptions {
  daemonToken: string;
  requestShutdown: (source: string) => void;
  getStatus: () => DaemonStatus;
}

// ── Body parser ────────────────────────────────────────────────

function collectBody(req: IncomingMessage): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf-8")));
    req.on("error", reject);
  });
}

// ── Helpers ────────────────────────────────────────────────────

function writeJson(
  res: ServerResponse,
  statusCode: number,
  data: unknown,
): void {
  const body = JSON.stringify(data);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
  });
  res.end(body);
}

function write404(res: ServerResponse): void {
  writeJson(res, 404, { error: "not found" });
}

function write401(res: ServerResponse): void {
  writeJson(res, 401, { error: "unauthorized" });
}

// ── Request handler factory ────────────────────────────────────

function createHandler(
  options: ControlServerOptions,
  startedAt: number,
  getServer: () => http.Server,
): (req: IncomingMessage, res: ServerResponse) => void {
  return async (req: IncomingMessage, res: ServerResponse) => {
    const url = req.url ?? "/";
    const method = req.method ?? "GET";

    // Handle CORS preflight
    if (method === "OPTIONS") {
      res.writeHead(204, {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      });
      res.end();
      return;
    }

    // ── GET /health ──────────────────────────────────────────
    if (method === "GET" && url === "/health") {
      writeJson(res, 200, {
        status: "ok",
        pid: process.pid,
        uptime: Math.floor((Date.now() - startedAt) / 1000),
      });
      return;
    }

    // ── GET /status ──────────────────────────────────────────
    if (method === "GET" && url === "/status") {
      const status = options.getStatus();
      writeJson(res, 200, status);
      return;
    }

    // ── POST /stop ───────────────────────────────────────────
    if (method === "POST" && url === "/stop") {
      const auth = req.headers["authorization"] ?? "";
      const expected = `Bearer ${options.daemonToken}`;

      if (auth !== expected) {
        write401(res);
        return;
      }

      // Consume body so the request is fully read before we respond
      await collectBody(req);

      writeJson(res, 200, { ok: true });

      // Shutdown after responding; the server closes itself.
      setImmediate(() => {
        options.requestShutdown("control-server");
        getServer().close();
      });
      return;
    }

    // ── 404 fallback ─────────────────────────────────────────
    write404(res);
  };
}

// ── Public API ─────────────────────────────────────────────────

export function startControlServer(
  options: ControlServerOptions,
): Promise<{ port: number; server: http.Server }> {
  const startedAt = Date.now();
  let server: http.Server;

  server = http.createServer(createHandler(options, startedAt, () => server));

  return new Promise<{ port: number; server: http.Server }>((resolve) => {
    server.listen(0, "127.0.0.1", () => {
      const addr = server.address();
      const port = typeof addr === "object" && addr ? addr.port : 0;
      resolve({ port, server });
    });
  });
}
