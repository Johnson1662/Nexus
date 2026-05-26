import qrcode from 'qrcode-terminal';
import { WebSocketServer } from "ws";
import os from "os";
import { getOrCreateHostId, getOrCreateHostIdentity } from "./host-identity.mjs";
import { RelayHost } from "./relay.mjs";
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
import { cleanupWsSessions, enqueueWsOp } from "./session.mjs";
const PORT = 12138;
const HOST = "0.0.0.0";
const RELAY_URL = process.env.ANYWHERE_RELAY_URL || "ws://35.212.247.127:12138";
const wss = new WebSocketServer({ host: HOST, port: PORT });
console.log(`[server] listening on ws://${HOST}:${PORT}`);
const HOST_ID = getOrCreateHostId();
let relayWsAdapter = null;
const relay = new RelayHost(RELAY_URL, HOST_ID, (raw) => {
    console.log(`[relay] received ${raw.slice(0, 120)}`);
    if (relayWsAdapter) {
        relayWsAdapter.emit("message", Buffer.from(raw));
    }
});
import { EventEmitter } from "events";
class RelayWsAdapter extends EventEmitter {
    send(data) {
        relay.send(data);
    }
    get readyState() {
        return relay.isReady() ? 1 : 3;
    }
}
relayWsAdapter = new RelayWsAdapter();
// When the relay connection drops, trigger cleanup on the adapter
relay.onDisconnect(() => {
    console.log("[server] Relay disconnected, cleaning up relay sessions");
    if (relayWsAdapter) {
        relayWsAdapter.emit("close");
    }
});
// Print QR code after relay connects
const relayHostIdentity = getOrCreateHostIdentity();
relay.connect();
setTimeout(() => {
    const qrData = JSON.stringify({
        relayUrl: RELAY_URL,
        hostId: relayHostIdentity.hostId,
        publicKey: relayHostIdentity.publicKeyHex,
    });
    console.log('\n[QR] Scan this code in Anywhere App to connect:\n');
    qrcode.generate(qrData, { small: true });
}, 1000);
function sendServerInfo(ws) {
    try {
        const hostname = os.hostname();
        const nets = os.networkInterfaces();
        const ips = [];
        for (const name of Object.keys(nets)) {
            for (const net of nets[name]) {
                if (!net.internal) {
                    ips.push(net.address);
                }
            }
        }
        ips.push(`HOST:${HOST_ID}`);
        ws.send(JSON.stringify({
            type: "server_info",
            hostId: HOST_ID,
            relayPin: HOST_ID,
            hostname,
            ips,
        }));
        console.log(`[server] sent server_info: ${hostname} (${ips.length} IPs)`);
    }
    catch (err) {
        console.log(`[server] failed to get host info: ${err}`);
    }
}
function handleIncomingConnection(ws, isRelay = false) {
    console.log(`[server] ${isRelay ? 'Relay' : 'Local'} client connected`);
    sendServerInfo(ws);
    ws.on("message", (raw) => {
        let msg;
        try {
            msg = JSON.parse(raw.toString());
        }
        catch {
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
                enqueueWsOp(ws, () => handleStart(ws, msg));
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
                handleSwitchModel(ws, msg.sessionId, msg.model).catch((err) => {
                    console.log(`[server] handleSwitchModel error: ${err.message}`);
                });
                break;
            case "list_models":
                console.log(`[server] handleListModels agent="${msg.agent || ""}"`);
                enqueueWsOp(ws, () => handleListModels(ws, msg.agent));
                break;
            case "list_sessions":
                console.log(`[server] handleListSessions cwd="${msg.cwd || ""}" agent="${msg.agent || ""}"`);
                enqueueWsOp(ws, () => handleListSessions(ws, msg.cwd, msg.agent));
                break;
            case "set_mode":
                console.log(`[server] handleSetMode session="${msg.sessionId?.slice(0, 20)}" mode="${msg.modeId}"`);
                handleSetMode(ws, msg.sessionId, msg.modeId).catch((err) => {
                    console.log(`[server] handleSetMode error: ${err.message}`);
                });
                break;
            case "set_config":
                console.log(`[server] handleSetConfig session="${msg.sessionId?.slice(0, 20)}" config="${msg.configId}" value="${msg.value}"`);
                handleSetConfig(ws, msg.sessionId, msg.configId, msg.value).catch((err) => {
                    console.log(`[server] handleSetConfig error: ${err.message}`);
                });
                break;
            case "load_session":
                console.log(`[server] handleLoadSession target="${msg.sessionId?.slice(0, 20)}" agent="${msg.agent || "opencode"}"`);
                handleLoadSession(ws, msg).catch((err) => {
                    console.log(`[server] handleLoadSession error: ${err.message}`);
                });
                break;
            case "resume_session":
                console.log(`[server] handleResumeSession target="${msg.sessionId?.slice(0, 20)}" agent="${msg.agent || "opencode"}"`);
                handleResumeSession(ws, msg).catch((err) => {
                    console.log(`[server] handleResumeSession error: ${err.message}`);
                });
                break;
            case "close_session":
                console.log(`[server] handleCloseSession session="${msg.sessionId?.slice(0, 20)}"`);
                handleCloseSession(ws, msg.sessionId).catch((err) => {
                    console.log(`[server] handleCloseSession error: ${err.message}`);
                });
                break;
            case "permission_response":
                console.log(`[server] handlePermissionResponse session="${msg.sessionId?.slice(0, 20)}" outcome="${msg.outcome}"`);
                handlePermissionResponse(ws, msg.sessionId, msg.requestId, msg.outcome, msg.optionId);
                break;
            case "authenticate":
                console.log(`[server] handleAuth session="${msg.sessionId?.slice(0, 20)}" method="${msg.methodId}"`);
                handleAuth(ws, msg.sessionId, msg.methodId).catch((err) => {
                    console.log(`[server] handleAuth error: ${err.message}`);
                });
                break;
            default:
                if (isRelay && msg.type === 'relay_client_connected') {
                    console.log('[server] new client via relay, resending server_info');
                    sendServerInfo(ws);
                }
                else {
                    console.log(`[server] unknown message type: ${msg.type}`);
                }
        }
    });
    ws.on("close", () => {
        console.log(`[server] ${isRelay ? 'Relay' : 'Local'} client disconnected, cleaning up sessions`);
        clearSessionListCache(ws);
        cleanupWsSessions(ws);
    });
}
handleIncomingConnection(relayWsAdapter, true);
wss.on("connection", (ws) => {
    handleIncomingConnection(ws, false);
});
//# sourceMappingURL=server.mjs.map