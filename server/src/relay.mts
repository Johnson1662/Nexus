import WebSocket from 'ws';

export class RelayHost {
  private ws: WebSocket | null = null;
  private onDisconnectCallback: (() => void) | null = null;
  private reconnectDelayMs = 5_000;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  public deviceId: string;

  constructor(private relayUrl: string, hostId: string, private onMessage: (msg: string) => void) {
    this.deviceId = hostId;
  }

  onDisconnect(cb: () => void): void {
    this.onDisconnectCallback = cb;
  }

  connect() {
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    const url = `${this.relayUrl}?role=host&deviceId=${this.deviceId}`;
    console.log(`[Relay] Connecting to ${url}`);
    this.ws = new WebSocket(url);

    this.ws.on('open', () => {
      console.log(`[Relay] Connected! HostId: ${this.deviceId}`);
      this.reconnectDelayMs = 5_000;
    });

    this.ws.on('message', (data: WebSocket.RawData) => {
      this.onMessage(data.toString());
    });

    this.ws.on('close', () => {
      const delay = this.reconnectDelayMs;
      console.log(`[Relay] Disconnected, reconnecting in ${Math.floor(delay / 1000)}s...`);
      if (this.onDisconnectCallback) {
        this.onDisconnectCallback();
      }
      this.ws = null;
      this.reconnectTimer = setTimeout(() => this.connect(), delay);
      this.reconnectDelayMs = Math.min(this.reconnectDelayMs * 2, 30_000);
    });

    this.ws.on('error', (err) => {
      console.log(`[Relay] WebSocket error: ${err.message}`);
    });
  }

  send(data: string) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    this.ws.send(data);
  }

  isReady(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }
}
