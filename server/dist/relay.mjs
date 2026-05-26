import WebSocket from 'ws';
export class RelayHost {
    relayUrl;
    onMessage;
    ws = null;
    onDisconnectCallback = null;
    deviceId;
    constructor(relayUrl, hostId, onMessage) {
        this.relayUrl = relayUrl;
        this.onMessage = onMessage;
        this.deviceId = hostId;
    }
    onDisconnect(cb) {
        this.onDisconnectCallback = cb;
    }
    connect() {
        const url = `${this.relayUrl}?role=host&deviceId=${this.deviceId}`;
        console.log(`[Relay] Connecting to ${url}`);
        this.ws = new WebSocket(url);
        this.ws.on('open', () => {
            console.log(`[Relay] Connected! HostId: ${this.deviceId}`);
        });
        this.ws.on('message', (data) => {
            this.onMessage(data.toString());
        });
        this.ws.on('close', () => {
            console.log('[Relay] Disconnected, reconnecting in 5s...');
            if (this.onDisconnectCallback) {
                this.onDisconnectCallback();
            }
            setTimeout(() => this.connect(), 5000);
        });
        this.ws.on('error', (err) => {
            console.log(`[Relay] WebSocket error: ${err.message}`);
        });
    }
    send(data) {
        if (!this.ws || this.ws.readyState !== WebSocket.OPEN)
            return;
        this.ws.send(data);
    }
    isReady() {
        return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
    }
}
//# sourceMappingURL=relay.mjs.map