import WebSocket from 'ws';
import crypto from 'crypto';
export class RelayHost {
    relayUrl;
    onMessage;
    ws = null;
    deviceId;
    constructor(relayUrl, onMessage) {
        this.relayUrl = relayUrl;
        this.onMessage = onMessage;
        this.deviceId = crypto.randomBytes(4).toString('hex').toUpperCase();
    }
    connect() {
        const url = `${this.relayUrl}?role=host&deviceId=${this.deviceId}`;
        console.log(`[Relay] Connecting to ${url}`);
        this.ws = new WebSocket(url);
        this.ws.on('open', () => {
            console.log(`[Relay] Connected! Your PIN is: ${this.deviceId}`);
        });
        this.ws.on('message', (data) => {
            this.onMessage(data.toString());
        });
        this.ws.on('close', () => {
            console.log('[Relay] Disconnected, reconnecting in 5s...');
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
}
//# sourceMappingURL=relay.mjs.map