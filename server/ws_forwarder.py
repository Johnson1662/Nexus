#!/usr/bin/env python3
"""Lightweight WS forwarder (compat websockets 9.x)."""
import asyncio
import websockets

CF_WORKER_URL = "wss://anywhere-relay.zcly12138.workers.dev/ws"

async def forward(src, dst, label):
    try:
        async for msg in src:
            await dst.send(msg)
    except websockets.exceptions.ConnectionClosed:
        pass
    except Exception as e:
        print(f"[fwd] {label} err: {e}", flush=True)

async def handle_client(ws, path):
    query = ""
    if "?" in path:
        query = path[path.index("?"):]
    upstream = CF_WORKER_URL + query
    print(f"[fwd] client -> {upstream}", flush=True)
    try:
        async with websockets.connect(upstream, ping_interval=30, ping_timeout=10) as up:
            t1 = asyncio.create_task(forward(ws, up, "c→u"))
            t2 = asyncio.create_task(forward(up, ws, "u→c"))
            done, pending = await asyncio.wait([t1, t2], return_when=asyncio.FIRST_COMPLETED)
            for t in pending:
                t.cancel()
    except websockets.exceptions.WebSocketException as e:
        print(f"[fwd] upstream failed: {e}", flush=True)
    except Exception as e:
        print(f"[fwd] err: {e}", flush=True)

async def main():
    print("[fwd] listen on ws://0.0.0.0:12138 -> " + CF_WORKER_URL, flush=True)
    async with websockets.serve(handle_client, "0.0.0.0", 12138):
        await asyncio.Future()

asyncio.run(main())
