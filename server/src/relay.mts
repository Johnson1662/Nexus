import WebSocket from 'ws';

export class RelayHost {
  private ws: WebSocket | null = null;
  public deviceId: string;

  constructor(private relayUrl: string, hostId: string, private onMessage: (msg: string) => void) {
    this.deviceId = hostId;
  }

  connect() {
    const url = `${this.relayUrl}?role=host&deviceId=${this.deviceId}`;
    console.log(`[Relay] Connecting to ${url}`);
    this.ws = new WebSocket(url);

    this.ws.on('open', () => {
      console.log(`[Relay] Connected! HostId: ${this.deviceId}`);
    });

    this.ws.on('message', (data: WebSocket.RawData) => {
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

  send(data: string) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    this.ws.send(data);
  }

  isReady(): boolean {
    return this.ws !== null && this.ws.readyState === WebSocket.OPEN;
  }
}
