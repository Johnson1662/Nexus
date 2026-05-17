import { WebSocketServer, type WebSocket } from "ws";
import { discoverAgents } from "./discovery/agents.mjs";
import { handleStart } from "./handlers/start.mjs";
import { handleInput } from "./handlers/input.mjs";
import { handleCancel } from "./handlers/cancel.mjs";
import { handleListModels } from "./handlers/list-models.mjs";
import { handleListSessions, clearSessionListCache } from "./handlers/list-sessions.mjs";
import { handleSetMode } from "./handlers/set-mode.mjs";
import { handleSwitchModel } from "./handlers/switch-model.mjs";
import { handleLoadSession } from "./handlers/load-session.mjs";
import { handleResumeSession } from "./handlers/resume-session.mjs";
import { handleCloseSession } from "./handlers/close-session.mjs";
import { handleSetConfig } from "./handlers/set-config.mjs";
import { handlePermissionResponse } from "./handlers/permission.mjs";
import { handleAuth } from "./handlers/auth.mjs";
import { cleanupWsSessions } from "./session.mjs";

const PORT = 12138;
const HOST = "0.0.0.0";

const wss = new WebSocketServer({ host: HOST, port: PORT });
console.log(`[server] listening on ws://${HOST}:${PORT}`);

wss.on("connection", (ws: WebSocket) => {
  console.log("[server] client connected");

  ws.on("message", (raw: Buffer) => {
    let msg: any;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      ws.send(JSON.stringify({ type: "error", text: "invalid json" }));
      return;
    }

    const logPrefix = `[server] ← ${msg.type}`;
    const logDetails = msg.text ? ` text="${msg.text.slice(0, 60)}"` :
      msg.sessionId ? ` sessionId="${msg.sessionId?.slice(0, 20)}"` : '';
    console.log(`${logPrefix}${logDetails}`);

    switch (msg.type) {
      case "start":
        console.log(`[server] handleStart agent="${msg.agent || "opencode"}" cwd="${msg.cwd || process.cwd()}"`);
        clearSessionListCache(ws);
        handleStart(ws, msg).catch((err: Error) => {
          console.log(`[server] handleStart error: ${err.message}`);
        });
        break;

      case "list_agents": {
        const agents = discoverAgents();
        console.log(`[server] → agent_list (${agents.length} agents)`);
        ws.send(JSON.stringify({ type: "agent_list", agents }));
        break;
      }

      case "input":
        console.log(`[server] handleInput session="${msg.sessionId?.slice(0, 20)}" text="${msg.text?.slice(0, 80)}"`);
        handleInput(ws, msg.sessionId, msg.text);
        break;

      case "cancel":
        console.log(`[server] handleCancel session="${msg.sessionId?.slice(0, 20)}"`);
        handleCancel(ws, msg.sessionId);
        break;

      case "switch_model":
        console.log(`[server] handleSwitchModel session="${msg.sessionId?.slice(0, 20)}" model="${msg.model}"`);
        handleSwitchModel(ws, msg.sessionId, msg.model).catch((err: Error) => {
          console.log(`[server] handleSwitchModel error: ${err.message}`);
        });
        break;

      case "list_models":
        console.log(`[server] handleListModels`);
        handleListModels(ws).catch((err: Error) => {
          console.log(`[server] handleListModels error: ${err.message}`);
        });
        break;

      case "list_sessions":
        console.log(`[server] handleListSessions cwd="${msg.cwd || ""}"`);
        handleListSessions(ws, msg.cwd).catch((err: Error) => {
          console.log(`[server] handleListSessions error: ${err.message}`);
        });
        break;

      case "set_mode":
        console.log(`[server] handleSetMode session="${msg.sessionId?.slice(0, 20)}" mode="${msg.modeId}"`);
        handleSetMode(ws, msg.sessionId, msg.modeId).catch((err: Error) => {
          console.log(`[server] handleSetMode error: ${err.message}`);
        });
        break;

      case "set_config":
        console.log(`[server] handleSetConfig session="${msg.sessionId?.slice(0, 20)}" config="${msg.configId}" value="${msg.value}"`);
        handleSetConfig(ws, msg.sessionId, msg.configId, msg.value).catch((err: Error) => {
          console.log(`[server] handleSetConfig error: ${err.message}`);
        });
        break;

      case "load_session":
        console.log(`[server] handleLoadSession target="${msg.sessionId?.slice(0, 20)}" agent="${msg.agent || "opencode"}"`);
        handleLoadSession(ws, msg).catch((err: Error) => {
          console.log(`[server] handleLoadSession error: ${err.message}`);
        });
        break;

      case "resume_session":
        console.log(`[server] handleResumeSession target="${msg.sessionId?.slice(0, 20)}" agent="${msg.agent || "opencode"}"`);
        handleResumeSession(ws, msg).catch((err: Error) => {
          console.log(`[server] handleResumeSession error: ${err.message}`);
        });
        break;

      case "close_session":
        console.log(`[server] handleCloseSession session="${msg.sessionId?.slice(0, 20)}"`);
        handleCloseSession(ws, msg.sessionId).catch((err: Error) => {
          console.log(`[server] handleCloseSession error: ${err.message}`);
        });
        break;

      case "permission_response":
        console.log(`[server] handlePermissionResponse session="${msg.sessionId?.slice(0, 20)}" outcome="${msg.outcome}"`);
        handlePermissionResponse(
          ws,
          msg.sessionId,
          msg.requestId,
          msg.outcome,
          msg.optionId,
        );
        break;

      case "authenticate":
        console.log(`[server] handleAuth session="${msg.sessionId?.slice(0, 20)}" method="${msg.methodId}"`);
        handleAuth(ws, msg.sessionId, msg.methodId).catch((err: Error) => {
          console.log(`[server] handleAuth error: ${err.message}`);
        });
        break;

      default:
        console.log(`[server] unknown message type: ${msg.type}`);
    }
  });

  ws.on("close", () => {
    console.log("[server] client disconnected, cleaning up sessions");
    clearSessionListCache(ws);
    cleanupWsSessions(ws);
  });
});
