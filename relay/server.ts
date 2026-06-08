import http from 'node:http';
import crypto from 'node:crypto';

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const PORT = parseInt(process.env.RELAY_PORT || '12138', 10);

// --------------- Minimal WebSocket ---------------

function encodeFrame(payload: Buffer, opcode: number): Buffer {
  const len = payload.length;
  let header: Buffer;
  if (len < 126) {
    header = Buffer.alloc(2);
    header[1] = len;
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  header[0] = 0x80 | opcode;
  return Buffer.concat([header, payload]);
}

class WSConn {
  data: any = {};
  onmessage: ((data: Buffer) => void) | null = null;
  onclose: (() => void) | null = null;

  private socket: any;
  private buf = Buffer.alloc(0);

  constructor(socket: any) {
    this.socket = socket;
    socket.on('data', (d: Buffer) => this._feed(d));
    socket.on('close', () => this.onclose?.());
  }

  send(data: string | Buffer) {
    const buf = typeof data === 'string' ? Buffer.from(data) : data;
    this.socket.write(encodeFrame(buf, 0x02));
  }

  close(code = 1000, reason = '') {
    this.socket.end(encodeFrame(Buffer.from(reason), 0x08));
  }

  private _feed(data: Buffer) {
    this.buf = Buffer.concat([this.buf, data]);
    while (this.buf.length >= 2) {
      const n = this._tryParse();
      if (n === 0) break;
      this.buf = this.buf.slice(n);
    }
  }

  private _tryParse(): number {
    const b = this.buf;
    const opcode = b[0] & 0x0F;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7F;
    let off = 2;

    if (len === 126) { if (b.length < 4) return 0; len = b.readUInt16BE(2); off = 4; }
    else if (len === 127) { if (b.length < 10) return 0; len = Number(b.readBigUInt64BE(2)); off = 10; }

    const maskLen = masked ? 4 : 0;
    if (b.length < off + maskLen + len) return 0;

    let payload: Buffer;
    if (masked) {
      const mask = b.subarray(off, off + 4);
      payload = Buffer.allocUnsafe(len);
      for (let i = 0; i < len; i++) payload[i] = b[off + 4 + i] ^ mask[i & 3];
    } else {
      payload = b.subarray(off, off + len);
    }

    if (opcode === 0x08) { this.socket.end(); return off + maskLen + len; }
    if (opcode === 0x01 || opcode === 0x02) this.onmessage?.(payload);
    return off + maskLen + len;
  }
}

// --------------- Relay Logic ---------------

const hosts = new Map<string, WSConn>();
const clients = new Map<string, Set<WSConn>>();

const server = http.createServer((_req, res) => {
  res.writeHead(400).end('WebSocket only');
});

server.on('upgrade', (req, socket) => {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  const role = url.searchParams.get('role');
  const hostId = role === 'host'
    ? url.searchParams.get('deviceId')
    : url.searchParams.get('targetHostId');

  if (!role || !hostId || (role !== 'host' && role !== 'client')) {
    socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    return;
  }

  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.end('HTTP/1.1 400 Bad Request\r\n\r\n'); return; }

  const accept = crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    'Sec-WebSocket-Accept: ' + accept + '\r\n\r\n'
  );
  socket.setNoDelay(true);

  const ws = new WSConn(socket);
  ws.data = { role, hostId };
  console.log(`[OPEN] ${role} connected. Target/Self hostId: ${hostId}`);

  if (role === 'host') {
    const old = hosts.get(hostId);
    if (old) old.close(1008, 'New host connected');
    hosts.set(hostId, ws);
    const waitingClients = clients.get(hostId);
    if (waitingClients && waitingClients.size > 0) {
      ws.send(JSON.stringify({ type: 'relay_client_connected' }));
      console.log(`[NOTIFY] host ${hostId} about ${waitingClients.size} waiting client(s)`);
    }
  } else {
    let set = clients.get(hostId);
    if (!set) { set = new Set(); clients.set(hostId, set); }
    set.add(ws);
    // Notify host about new client
    const hostWs = hosts.get(hostId);
    if (hostWs) {
      hostWs.send(JSON.stringify({ type: 'relay_client_connected' }));
      console.log(`[NOTIFY] host ${hostId} about new client`);
    } else {
      ws.send(JSON.stringify({ type: 'target_offline', hostId }));
      console.log(`[NOTIFY] client ${hostId} target offline`);
    }
  }

  ws.onmessage = (msg) => {
    const { role: r, hostId: h } = ws.data;
    console.log(`[MSG] from=${r} target=${h} bytes=${msg.length}`);

    if (r === 'client') {
      const hw = hosts.get(h);
      if (hw) hw.send(msg);
      else {
        ws.send(JSON.stringify({ type: 'target_offline', hostId: h }));
        console.log(`[WARN] No host found for hostId: ${h}`);
      }
    } else if (r === 'host') {
      const set = clients.get(h);
      if (set) for (const cw of set) cw.send(msg);
    }
  };

  ws.onclose = () => {
    const { role: r, hostId: h } = ws.data;
    console.log(`[CLOSE] ${r} disconnected: ${h}`);
    if (r === 'host' && hosts.get(h) === ws) hosts.delete(h);
    else if (r === 'client') {
      const set = clients.get(h);
      if (set) { set.delete(ws); if (set.size === 0) clients.delete(h); }
    }
  };
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Relay server running on ws://0.0.0.0:${PORT}`);
});
