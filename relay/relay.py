#!/usr/bin/env python3
"""Anywhere Relay Server — zero-dependency WebSocket relay using asyncio."""

import asyncio
import hashlib
import base64
import struct
import os
import signal
import sys

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
PORT = int(os.environ.get("RELAY_PORT", "12138"))

hosts = {}
clients = {}
pending_frames = {}



def make_accept(key):
    digest = hashlib.sha1((key + WS_GUID).encode()).digest()
    return base64.b64encode(digest).decode()


def encode_frame(payload, opcode=0x02):
    data = payload if isinstance(payload, bytes) else payload.encode()
    n = len(data)
    if n < 126:
        header = struct.pack("!BB", 0x80 | opcode, n)
    elif n < 65536:
        header = struct.pack("!BBH", 0x80 | opcode, 126, n)
    else:
        header = struct.pack("!BBQ", 0x80 | opcode, 127, n)
    return header + data


class WSConnection:
    __slots__ = ("transport", "buf", "role", "host_id", "on_msg", "on_close")

    def __init__(self, transport, role, host_id):
        self.transport = transport
        self.buf = b""
        self.role = role
        self.host_id = host_id
        self.on_msg = None
        self.on_close = None

    def send(self, data):
        if isinstance(data, str):
            data = data.encode()
        try:
            self.transport.write(encode_frame(data))
        except Exception:
            pass

    def feed(self, data):
        self.buf += data
        while len(self.buf) >= 2:
            consumed = self._parse()
            if consumed == 0:
                break
            self.buf = self.buf[consumed:]

    def _parse(self):
        b = self.buf
        first = b[0]
        opcode = first & 0x0F
        second = b[1]
        masked = bool(second & 0x80)
        length = second & 0x7F
        off = 2

        if length == 126:
            if len(b) < 4:
                return 0
            length = struct.unpack_from("!H", b, 2)[0]
            off = 4
        elif length == 127:
            if len(b) < 10:
                return 0
            length = struct.unpack_from("!Q", b, 2)[0]
            off = 10

        mask_len = 4 if masked else 0
        if len(b) < off + mask_len + length:
            return 0

        if masked:
            mask = b[off:off + 4]
            payload = bytearray(length)
            for i in range(length):
                payload[i] = b[off + 4 + i] ^ mask[i & 3]
            payload = bytes(payload)
        else:
            payload = b[off:off + length]

        total = off + mask_len + length

        if opcode == 0x08:
            self.close_conn()
            return total

        if opcode == 0x09:
            # Respond to ping with pong
            self.transport.write(encode_frame(payload, 0x0A))
            return total

        if opcode in (0x01, 0x02) and self.on_msg:
            self.on_msg(payload)

        return total

    def close_conn(self):
        try:
            self.transport.close()
        except Exception:
            pass

    def cleanup(self):
        h = self.host_id
        if self.role == "host":
            if hosts.get(h) is self:
                hosts.pop(h, None)
        elif self.role == "client":
            s = clients.get(h)
            if s:
                s.discard(self)
                if not s:
                    clients.pop(h, None)


class RelayServerProtocol(asyncio.Protocol):
    def connection_made(self, transport):
        self.transport = transport
        self._ws = None

    def data_received(self, data):
        if self._ws is None:
            self._try_upgrade(data)
        else:
            self._ws.feed(data)

    def _try_upgrade(self, data):
        # Parse HTTP request
        text = data.decode("latin-1", errors="replace")
        lines = text.split("\r\n")
        if not lines:
            self.transport.close()
            return

        method, path, _ = lines[0].split(" ", 2)
        if method != "GET":
            self._http_response(400, "Bad Request")
            return

        headers = {}
        for line in lines[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        upgrade = headers.get("upgrade", "").lower()
        if upgrade != "websocket":
            self._http_response(400, "WebSocket only")
            return

        key = headers.get("sec-websocket-key", "")
        if not key:
            self._http_response(400, "Missing key")
            return

        # Parse URL params
        if "?" in path:
            qs = path.split("?", 1)[1]
            params = dict(p.split("=", 1) for p in qs.split("&") if "=" in p)
        else:
            params = {}

        role = params.get("role")
        host_id = params.get("deviceId") if role == "host" else params.get("targetHostId")

        if not role or not host_id or role not in ("host", "client"):
            self._http_response(400, "Missing or invalid role/deviceId")
            return

        # WebSocket upgrade response
        accept = make_accept(key)
        resp = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        )
        self.transport.write(resp.encode())
        try:
            self.transport.get_extra_info("socket", default=None)
        except Exception:
            pass

        ws = WSConnection(self.transport, role, host_id)
        self._ws = ws

        print(f"[OPEN] {role} connected. Target/Self hostId: {host_id}")

        if role == "host":
            old = hosts.get(host_id)
            if old:
                old.close_conn()
            hosts[host_id] = ws
            
            # Flush any pending frames for this host
            q = pending_frames.pop(host_id, [])
            if q:
                print(f"[FLUSH] sending {len(q)} buffered frames to host {host_id}")
                for m in q:
                    ws.send(m)

        else:
            s = clients.get(host_id)
            if s is None:
                s = set()
                clients[host_id] = s
            s.add(ws)

            host_ws = hosts.get(host_id)
            if host_ws:
                host_ws.send('{"type":"relay_client_connected"}')
                print(f"[NOTIFY] host {host_id} about new client")

        def on_msg(msg):
            h = ws.host_id
            print(f"[MSG] from={ws.role} target={h} bytes={len(msg)}")
            if ws.role == "client":
                hw = hosts.get(h)
                if hw:
                    hw.send(msg)
                else:
                    print(f"[WARN] No host found for hostId: {h}, buffering...")
                    q = pending_frames.setdefault(h, [])
                    if len(q) < 200:
                        q.append(msg)
            elif ws.role == "host":
                cs = clients.get(h)
                if cs:
                    for c in cs:
                        c.send(msg)

        def on_close():
            ws.cleanup()
            print(f"[CLOSE] {ws.role} disconnected: {ws.host_id}")

        ws.on_msg = on_msg
        ws.on_close = on_close

    def connection_lost(self, exc):
        if self._ws and self._ws.on_close:
            self._ws.on_close()

    def _http_response(self, code, msg):
        reasons = {400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"}
        reason = reasons.get(code, "Unknown")
        body = f"{code} {reason}\r\n"
        resp = (
            f"HTTP/1.1 {code} {reason}\r\n"
            f"Content-Length: {len(body)}\r\n"
            f"Content-Type: text/plain\r\n"
            f"Connection: close\r\n\r\n{body}"
        )
        try:
            self.transport.write(resp.encode())
            self.transport.close()
        except Exception:
            pass


async def main():
    loop = asyncio.get_event_loop()
    server = await loop.create_server(
        RelayServerProtocol, "0.0.0.0", PORT
    )
    print(f"Relay server running on ws://0.0.0.0:{PORT}")

    # Handle shutdown
    stop = asyncio.Future()

    def shutdown():
        if not stop.done():
            stop.set_result(True)

    try:
        loop.add_signal_handler(signal.SIGTERM, shutdown)
        loop.add_signal_handler(signal.SIGINT, shutdown)
    except (NotImplementedError, AttributeError):
        pass  # Windows or restricted platforms without signal support

    async with server:
        await stop

    print("Relay server stopped.")


if __name__ == "__main__":
    asyncio.run(main())
