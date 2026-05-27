import qrcode from 'qrcode-terminal';
import { WebSocketServer } from "ws";
import os from "os";
import { getOrCreateHostId, getOrCreateHostIdentity } from "./host-identity.mjs";
import { EncryptedChannel } from "./encrypted-channel.mjs";
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
import { cleanupWsSessions, enqueueWsOp, getSession, getBufferedAfter, reclaimOrphanedSession } from "./session.mjs";
const PORT = 12138;
const HOST = "0.0.0.0";
const RELAY_URL = process.env.ANYWHERE_RELAY_URL || "wss://cf-relay.anywhere12138.lat/ws";
const PHONE_RELAY_URL = process.env.ANYWHERE_PHONE_RELAY_URL || "ws://relay.anywhere12138.lat:12138";
const wss = new WebSocketServer({ host: HOST, port: PORT });
console.log(`[server] listening on ws://${HOST}:${PORT}`);
const HOST_ID = getOrCreateHostId();
// The relay message handler is wired directly into handleIncomingConnection
// via a shared callback, bypassing the EventEmitter indirection which has
// proven unreliable for message delivery ordering.
let handleRelayMessage = null;
const relay = new RelayHost(RELAY_URL, HOST_ID, (raw) => {
    console.log(`[relay] received ${raw.slice(0, 120)}`);
    if (handleRelayMessage) {
        handleRelayMessage(raw);
    }
});
// Shared relay transport — messages delivered directly (no EventEmitter)
class RelayTransport {
    msgCb = null;
    closeCb = null;
    _closed = false;
    onMessage(cb) { this.msgCb = cb; }
    onClose(cb) { this.closeCb = cb; }
    send(data) {
        relay.send(typeof data === 'string' ? data : data.toString('utf-8'));
    }
    close() {
        if (this._closed)
            return;
        this._closed = true;
        if (this.closeCb)
            this.closeCb();
    }
    get readyState() { return relay.isReady() ? 1 : 3; }
    deliver(raw) { if (this.msgCb)
        this.msgCb(raw); }
}
let relayTransport = new RelayTransport();
handleRelayMessage = (raw) => { relayTransport.deliver(raw); };
relay.onDisconnect(() => {
    console.log("[server] Relay disconnected, cleaning up relay sessions");
    relayTransport.close();
});
// Print QR code after relay connects
const relayHostIdentity = getOrCreateHostIdentity();
relay.connect();
function printQR() {
    const offer = {
        v: 1,
        hostId: relayHostIdentity.hostId,
        ecdhPublicKeyHex: relayHostIdentity.publicKeyHex,
        ed25519PublicKeyHex: relayHostIdentity.ed25519PublicKeyHex,
        relayUrl: PHONE_RELAY_URL,
    };
    const encoded = Buffer.from(JSON.stringify(offer)).toString('base64url');
    const qrData = `anywhere://pair/#offer=${encoded}`;
    console.log('\n[QR] Scan this code in Anywhere App to connect:\n');
    qrcode.generate(qrData, { small: true });
}
setTimeout(printQR, 1000);
// Phase 3b: stdin listener — type any line + Enter to reprint QR
if (process.stdin.isTTY) {
    process.stdin.setEncoding('utf-8');
    process.stdin.on('data', () => {
        printQR();
    });
    console.log('[server] stdin: press Enter to re-display QR code');
}
// Phase 3b: environment variable — ANYWHERE_SHOW_QR=1 triggers reprint
if (process.env.ANYWHERE_SHOW_QR === '1') {
    printQR();
}
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
function handleIncomingConnection(transport, isRelay = false) {
    console.log(`[server] ${isRelay ? 'Relay' : 'Local'} client connected`);
    const identity = getOrCreateHostIdentity();
    const channels = new Map();
    // Heartbeat state per channel
    const heartbeatState = new Map();
    const HEARTBEAT_INTERVAL_MS = 10_000;
    const HEARTBEAT_TIMEOUT_MS = 30_000;
    function startHeartbeat(channelId, channel) {
        const state = { interval: null, lastHeard: Date.now() };
        state.interval = setInterval(() => {
            if (channel.getState() !== 'open') {
                stopHeartbeat(channelId);
                return;
            }
            channel.control('heartbeat', { ts: Date.now() });
            if (Date.now() - state.lastHeard > HEARTBEAT_TIMEOUT_MS) {
                console.log(`[server] heartbeat timeout for ${channelId}, closing channel`);
                channel.close();
            }
        }, HEARTBEAT_INTERVAL_MS);
        heartbeatState.set(channelId, state);
    }
    function stopHeartbeat(channelId) {
        const state = heartbeatState.get(channelId);
        if (state) {
            clearInterval(state.interval);
            heartbeatState.delete(channelId);
        }
    }
    function getOrCreateChannel(channelId) {
        let channel = channels.get(channelId);
        if (!channel) {
            channel = new EncryptedChannel({ role: 'host', hostIdentity: identity });
            channel.setEvents({
                onopen: () => {
                    console.log(`[server] E2EE handshake completed for ${channelId}`);
                    startHeartbeat(channelId, channel);
                },
                onclose: () => {
                    console.log(`[server] EncryptedChannel closed for ${channelId}`);
                    stopHeartbeat(channelId);
                    channels.delete(channelId);
                },
                onerror: (err) => console.log(`[server] EncryptedChannel error (${channelId}): ${err.message}`),
                oncontrol: (type, _payload) => {
                    if (type === 'heartbeat') {
                        const state = heartbeatState.get(channelId);
                        if (state)
                            state.lastHeard = Date.now();
                        return;
                    }
                    console.log(`[server] control message from ${channelId}: ${type}`);
                },
                onmessage: (data) => {
                    const rawStr = typeof data === 'string' ? data : Buffer.from(data).toString('utf-8');
                    handlePlaintextMessage(rawStr);
                },
            });
            channel.attachTransport({
                on: () => { },
                send: (data) => originalSend(data),
                close: () => { },
            });
            channels.set(channelId, channel);
        }
        return channel;
    }
    const originalSend = transport.send.bind(transport);
    // Override transport.send to broadcast business payloads via all open EncryptedChannels
    transport.send = (data) => {
        if (typeof data === 'string' && channels.size > 0) {
            let hasOpenChannel = false;
            for (const channel of channels.values()) {
                if (channel.getState() === 'open') {
                    channel.send(data).catch(() => { });
                    hasOpenChannel = true;
                }
            }
            if (hasOpenChannel)
                return;
        }
        originalSend(data);
    };
    sendServerInfo(transport);
    function handlePlaintextMessage(rawStr) {
        let msg;
        try {
            msg = JSON.parse(rawStr);
        }
        catch {
            // Some relays may strip quotes from JSON keys/values. Try to fix.
            try {
                const fixed = rawStr
                    .replace(/([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:/g, '$1"$2":')
                    .replace(/:\s*([a-zA-Z_][a-zA-Z0-9_.-]*)\s*([,}])/g, ':"$1"$2');
                msg = JSON.parse(fixed);
            }
            catch {
                transport.send(JSON.stringify({ type: "error", text: "invalid json" }));
                return;
            }
        }
        const logPrefix = `[server] ← ${msg.type}`;
        const logDetails = msg.text ? ` text="${msg.text.slice(0, 60)}"` :
            msg.sessionId ? ` sessionId="${msg.sessionId?.slice(0, 20)}"` : '';
        console.log(`${logPrefix}${logDetails}`);
        if (msg.sessionId) {
            const reclaimed = reclaimOrphanedSession(msg.sessionId, transport);
            if (reclaimed) {
                console.log(`[server] reclaimed orphaned session ${msg.sessionId?.slice(0, 20)}`);
            }
        }
        switch (msg.type) {
            case "start":
                console.log(`[server] handleStart agent="${msg.agent || "opencode"}" cwd="${msg.cwd || process.cwd()}"`);
                clearSessionListCache(transport);
                enqueueWsOp(transport, () => handleStart(transport, msg));
                break;
            case "list_agents": {
                let agents;
                try {
                    agents = discoverAgents();
                }
                catch (e) {
                    console.log(`[server] discoverAgents error: ${e}`);
                    agents = [];
                }
                console.log(`[server] → agent_list (${agents.length} agents)`);
                transport.send(JSON.stringify({ type: "agent_list", agents }));
                break;
            }
            case "input":
                console.log(`[server] handleInput session="${msg.sessionId?.slice(0, 20)}" text="${msg.text?.slice(0, 80)}"`);
                handleInput(transport, msg.sessionId, msg.text);
                break;
            case "cancel":
                console.log(`[server] handleCancel session="${msg.sessionId?.slice(0, 20)}"`);
                handleCancel(transport, msg.sessionId);
                break;
            case "switch_model":
                console.log(`[server] handleSwitchModel session="${msg.sessionId?.slice(0, 20)}" model="${msg.model}"`);
                handleSwitchModel(transport, msg.sessionId, msg.model).catch((err) => {
                    console.log(`[server] handleSwitchModel error: ${err.message}`);
                });
                break;
            case "list_models":
                console.log(`[server] handleListModels agent="${msg.agent || ""}"`);
                enqueueWsOp(transport, () => handleListModels(transport, msg.agent));
                break;
            case "list_sessions":
                console.log(`[server] handleListSessions cwd="${msg.cwd || ""}" agent="${msg.agent || ""}"`);
                enqueueWsOp(transport, () => handleListSessions(transport, msg.cwd, msg.agent));
                break;
            case "set_mode":
                console.log(`[server] handleSetMode session="${msg.sessionId?.slice(0, 20)}" mode="${msg.modeId}"`);
                handleSetMode(transport, msg.sessionId, msg.modeId).catch((err) => {
                    console.log(`[server] handleSetMode error: ${err.message}`);
                });
                break;
            case "set_config":
                console.log(`[server] handleSetConfig session="${msg.sessionId?.slice(0, 20)}" config="${msg.configId}" value="${msg.value}"`);
                handleSetConfig(transport, msg.sessionId, msg.configId, msg.value).catch((err) => {
                    console.log(`[server] handleSetConfig error: ${err.message}`);
                });
                break;
            case "load_session":
                console.log(`[server] handleLoadSession target="${msg.sessionId?.slice(0, 20)}" agent="${msg.agent || "opencode"}"`);
                handleLoadSession(transport, msg).catch((err) => {
                    console.log(`[server] handleLoadSession error: ${err.message}`);
                });
                break;
            case "resume_session":
                console.log(`[server] handleResumeSession target="${msg.sessionId?.slice(0, 20)}" agent="${msg.agent || "opencode"}"`);
                handleResumeSession(transport, msg).catch((err) => {
                    console.log(`[server] handleResumeSession error: ${err.message}`);
                });
                break;
            case "close_session":
                console.log(`[server] handleCloseSession session="${msg.sessionId?.slice(0, 20)}"`);
                handleCloseSession(transport, msg.sessionId).catch((err) => {
                    console.log(`[server] handleCloseSession error: ${err.message}`);
                });
                break;
            case "permission_response":
                console.log(`[server] handlePermissionResponse session="${msg.sessionId?.slice(0, 20)}" outcome="${msg.outcome}"`);
                handlePermissionResponse(transport, msg.sessionId, msg.requestId, msg.outcome, msg.optionId);
                break;
            case "authenticate":
                console.log(`[server] handleAuth session="${msg.sessionId?.slice(0, 20)}" method="${msg.methodId}"`);
                handleAuth(transport, msg.sessionId, msg.methodId).catch((err) => {
                    console.log(`[server] handleAuth error: ${err.message}`);
                });
                break;
            case "sync_request": {
                const syncSessionId = msg.sessionId;
                const lastMessageId = msg.lastMessageId || '';
                console.log(`[server] sync_request session="${syncSessionId?.slice(0, 20)}" lastMessageId="${lastMessageId?.slice(0, 20)}"`);
                const sess = getSession(syncSessionId);
                if (sess) {
                    const entries = getBufferedAfter(syncSessionId, lastMessageId);
                    const safeEntries = entries
                        .map(e => {
                        try {
                            return { messageId: e.messageId, payload: JSON.parse(e.payload), timestamp: e.timestamp };
                        }
                        catch {
                            return null;
                        }
                    })
                        .filter(Boolean);
                    transport.send(JSON.stringify({
                        type: "sync_response",
                        sessionId: syncSessionId,
                        entries: safeEntries,
                    }));
                    console.log(`[server] sync_response ${safeEntries.length} entries for ${syncSessionId?.slice(0, 20)}`);
                }
                else {
                    transport.send(JSON.stringify({
                        type: "sync_response",
                        sessionId: syncSessionId,
                        entries: [],
                        error: "session not found",
                    }));
                }
                break;
            }
            case "show_qr":
                console.log('[server] WS command: re-displaying QR code');
                printQR();
                transport.send(JSON.stringify({ type: "qr_displayed" }));
                break;
            default:
                if (isRelay && msg.type === 'relay_client_connected') {
                    console.log('[server] new client via relay, sending server_info');
                    originalSend(JSON.stringify({
                        type: "server_info",
                        hostId: HOST_ID,
                        relayPin: HOST_ID,
                        hostname: os.hostname(),
                        ips: []
                    }));
                }
                else {
                    console.log(`[server] unknown message type: ${msg.type}`);
                }
        }
    }
    // ── Incoming message handling ──
    function onRawBuffer(raw) {
        const buf = typeof raw === 'string' ? Buffer.from(raw) : raw;
        if (buf.length > 0 && (buf[0] === 0x7B || buf[0] === 0x22)) {
            const rawStr = buf.toString('utf-8');
            if (rawStr.includes('"e2ee_hello"') || rawStr.indexOf('type:e2ee_hello') >= 0) {
                // Forwarder may strip JSON quotes; try to fix before E2EE handler
                let parsedRaw = rawStr;
                try {
                    JSON.parse(rawStr);
                }
                catch {
                    try {
                        parsedRaw = rawStr
                            .replace(/([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:/g, '$1"$2":')
                            .replace(/:\s*([a-zA-Z_][a-zA-Z0-9_.-]*)\s*([,}])/g, ':"$1"$2');
                        JSON.parse(parsedRaw);
                    }
                    catch {
                        return;
                    }
                }
                try {
                    const parsed = JSON.parse(parsedRaw);
                    if (parsed.type === 'e2ee_hello' && parsed.ephemeralKey) {
                        const channelId = parsed.ephemeralKey.slice(0, 16);
                        const channel = getOrCreateChannel(channelId);
                        channel['handleControl'](parsedRaw);
                    }
                }
                catch { }
                return;
            }
            handlePlaintextMessage(rawStr);
        }
        else {
            if (buf.length >= 8) {
                const channelIdHex = buf.subarray(0, 8).toString('hex');
                const channel = channels.get(channelIdHex);
                if (channel) {
                    channel['handleBinary'](buf);
                }
                else {
                    console.log(`[server] unknown channelId: ${channelIdHex}, dropping binary frame`);
                }
            }
        }
    }
    function onClose() {
        console.log(`[server] ${isRelay ? 'Relay' : 'Local'} client disconnected, cleaning up sessions`);
        clearSessionListCache(transport);
        cleanupWsSessions(transport);
        for (const channelId of heartbeatState.keys()) {
            stopHeartbeat(channelId);
        }
        for (const channel of channels.values()) {
            channel.close();
        }
        channels.clear();
    }
    // Wire up message delivery based on transport type
    if (isRelay) {
        transport.onMessage((raw) => onRawBuffer(raw));
        transport.onClose(() => onClose());
    }
    else {
        transport.on("message", (raw) => onRawBuffer(raw));
        transport.on("close", () => onClose());
    }
}
handleIncomingConnection(relayTransport, true);
wss.on("connection", (ws) => {
    handleIncomingConnection(ws, false);
});
//# sourceMappingURL=server.mjs.map