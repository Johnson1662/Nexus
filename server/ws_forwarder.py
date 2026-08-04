#!/usr/bin/env python3
"""Authenticated WebSocket forwarder for the optional relay path.

The forwarder is deliberately loopback-only by default. It shares the bridge
Bearer token from NEXUS_AUTH_TOKEN or ~/.nexus/server.token and never accepts
credentials in a query string or in a post-upgrade message.
"""
from __future__ import annotations

import asyncio
import hmac
import inspect
import ipaddress
import os
import secrets
from http import HTTPStatus
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import websockets

DEFAULT_UPSTREAM_URL = "wss://nexus-relay.zcly12138.workers.dev/ws"
AUTH_TOKEN_ENV = "NEXUS_AUTH_TOKEN"
AUTH_TOKEN_FILE_ENV = "NEXUS_AUTH_TOKEN_FILE"
LISTEN_HOST_ENV = "NEXUS_FORWARDER_HOST"
LISTEN_PORT_ENV = "NEXUS_FORWARDER_PORT"
UPSTREAM_URL_ENV = "NEXUS_RELAY_URL"
ALLOW_NON_LOOPBACK_ENV = "NEXUS_ALLOW_NON_LOOPBACK"
SENSITIVE_QUERY_KEYS = frozenset(
    {"token", "auth", "authorization", "auth_token", "authtoken"}
)

AUTH_TOKEN: str | None = None


def _token_file() -> Path:
    configured = os.environ.get(AUTH_TOKEN_FILE_ENV)
    return Path(configured).expanduser() if configured else Path.home() / ".nexus" / "server.token"


def _read_or_create_token(path: Path) -> str:
    try:
        token = path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        path.parent.mkdir(parents=True, exist_ok=True)
        token = secrets.token_urlsafe(32)
        try:
            with path.open("x", encoding="utf-8", newline="") as handle:
                handle.write(token)
        except FileExistsError:
            token = path.read_text(encoding="utf-8").strip()
        else:
            try:
                os.chmod(path, 0o600)
            except OSError:
                pass
    except OSError as exc:
        raise RuntimeError(f"cannot read auth token file: {path}") from exc

    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    if not token:
        raise RuntimeError(f"auth token file is empty: {path}")
    return token


def load_auth_token() -> str:
    configured = os.environ.get(AUTH_TOKEN_ENV)
    if configured is not None:
        token = configured.strip()
        if not token:
            raise RuntimeError(f"{AUTH_TOKEN_ENV} must not be empty")
        return token
    return _read_or_create_token(_token_file())


def _header(headers: object, name: str) -> str | None:
    headers = getattr(headers, "headers", headers)
    getter = getattr(headers, "get", None)
    if not callable(getter):
        return None
    value = getter(name)
    return value.strip() if isinstance(value, str) else None


def _request_path(connection_or_path: object, request: object | None) -> str:
    path = getattr(request, "path", None)
    if isinstance(path, str):
        return path
    if isinstance(connection_or_path, str):
        return connection_or_path
    path = getattr(connection_or_path, "path", None)
    return path if isinstance(path, str) else "/ws"


def _connection_headers(connection: object) -> object:
    request_headers = getattr(connection, "request_headers", None)
    if request_headers is not None:
        return request_headers
    request = getattr(connection, "request", None)
    return getattr(request, "headers", None)


def is_authorized(headers: object) -> bool:
    expected = AUTH_TOKEN
    received = _header(headers, "Authorization")
    return bool(expected and received and hmac.compare_digest(received, f"Bearer {expected}"))


def _unauthorized_response():
    body = b"Unauthorized\n"
    headers = [
        ("Content-Type", "text/plain; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Connection", "close"),
    ]
    # websockets 14+ uses a Response object; older releases expect the tuple.
    if "asyncio.server" in getattr(websockets.serve, "__module__", ""):
        from websockets.datastructures import Headers
        from websockets.http11 import Response

        return Response(HTTPStatus.UNAUTHORIZED, "Unauthorized", Headers(headers), body)
    return HTTPStatus.UNAUTHORIZED, headers, body


async def process_request(connection_or_path, request=None):
    request_headers = getattr(request, "headers", request)
    if request is None:
        request_headers = _connection_headers(connection_or_path)
    if not is_authorized(request_headers):
        print("[fwd] rejected unauthenticated client", flush=True)
        return _unauthorized_response()
    return None


def _clean_query(path: str | None) -> str:
    if not path:
        return ""
    query = urlsplit(path).query
    return urlencode(
        [(key, value) for key, value in parse_qsl(query, keep_blank_values=True)
         if key.lower() not in SENSITIVE_QUERY_KEYS],
        doseq=True,
    )


def _clean_query_string(query: str) -> str:
    return urlencode(
        [(key, value) for key, value in parse_qsl(query, keep_blank_values=True)
         if key.lower() not in SENSITIVE_QUERY_KEYS],
        doseq=True,
    )


def upstream_url_for(path: str | None) -> str:
    base = urlsplit(os.environ.get(UPSTREAM_URL_ENV, DEFAULT_UPSTREAM_URL).strip())
    if base.scheme not in {"ws", "wss"} or not base.netloc:
        raise RuntimeError(f"{UPSTREAM_URL_ENV} must be a ws:// or wss:// URL")

    requested_query = _clean_query(path)
    base_query = _clean_query_string(base.query)
    query = "&".join(value for value in (base_query, requested_query) if value)
    return urlunsplit((base.scheme, base.netloc, base.path or "/", query, ""))


def _endpoint_for_log(url: str) -> str:
    parsed = urlsplit(url)
    host = parsed.hostname or ""
    if ":" in host and not host.startswith("["):
        host = f"[{host}]"
    if parsed.port:
        host = f"{host}:{parsed.port}"
    return urlunsplit((parsed.scheme, host, parsed.path or "/", "", ""))


def _upstream_connect(url: str):
    kwargs = {"ping_interval": 30, "ping_timeout": 10}
    try:
        parameters = inspect.signature(websockets.connect).parameters
    except (TypeError, ValueError):
        parameters = {}
    header_name = "additional_headers" if "additional_headers" in parameters else "extra_headers"
    kwargs[header_name] = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    return websockets.connect(url, **kwargs)


async def _close_socket(socket) -> None:
    close = getattr(socket, "close", None)
    if not callable(close):
        return
    try:
        result = close()
        if inspect.isawaitable(result):
            await asyncio.wait_for(result, timeout=1)
    except (Exception, asyncio.CancelledError):
        return


async def forward(src, dst, label: str) -> None:
    try:
        async for message in src:
            await dst.send(message)
    except asyncio.CancelledError:
        raise
    except websockets.exceptions.ConnectionClosed:
        return
    except Exception:
        # Avoid echoing exception text: a library error may contain a URL or
        # other request metadata that should not end up in relay logs.
        print(f"[fwd] {label} stream stopped", flush=True)


async def handle_client(ws, path=None) -> None:
    # process_request rejects before upgrade. Keep this check for websocket
    # versions that do not invoke process_request consistently.
    request_headers = _connection_headers(ws)
    if not is_authorized(request_headers):
        await _close_socket(ws)
        return

    request = getattr(ws, "request", None)
    request_path = path or _request_path(ws, request)
    upstream_url = upstream_url_for(request_path)
    print(f"[fwd] forwarding client to {_endpoint_for_log(upstream_url)}", flush=True)

    try:
        async with _upstream_connect(upstream_url) as upstream:
            client_to_upstream = asyncio.create_task(forward(ws, upstream, "client→relay"))
            upstream_to_client = asyncio.create_task(forward(upstream, ws, "relay→client"))
            tasks = {client_to_upstream, upstream_to_client}
            try:
                await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            finally:
                for task in tasks:
                    if not task.done():
                        task.cancel()
                await asyncio.gather(*tasks, return_exceptions=True)
                await _close_socket(upstream)
    except asyncio.CancelledError:
        raise
    except websockets.exceptions.WebSocketException:
        print("[fwd] upstream websocket failed", flush=True)
    except OSError:
        print("[fwd] upstream connection failed", flush=True)
    except Exception:
        print("[fwd] forwarding failed", flush=True)
    finally:
        await _close_socket(ws)


def _env_port() -> int:
    raw = os.environ.get(LISTEN_PORT_ENV, "12138")
    try:
        port = int(raw)
    except ValueError as exc:
        raise RuntimeError(f"{LISTEN_PORT_ENV} must be an integer") from exc
    if not 1 <= port <= 65535:
        raise RuntimeError(f"{LISTEN_PORT_ENV} must be between 1 and 65535")
    return port


def _is_loopback(host: str) -> bool:
    if host.lower() == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


async def main() -> None:
    global AUTH_TOKEN
    AUTH_TOKEN = load_auth_token()

    host = os.environ.get(LISTEN_HOST_ENV, "127.0.0.1").strip() or "127.0.0.1"
    if not _is_loopback(host):
        if os.environ.get(ALLOW_NON_LOOPBACK_ENV) != "1":
            raise RuntimeError(
                f"{LISTEN_HOST_ENV}={host!r} is not allowed; set "
                f"{ALLOW_NON_LOOPBACK_ENV}=1 explicitly to expose the authenticated relay"
            )
        print(f"[fwd] WARNING: non-loopback listener enabled on {host}", flush=True)

    port = _env_port()
    upstream = upstream_url_for("/ws")
    print(f"[fwd] listen on ws://{host}:{port} -> {_endpoint_for_log(upstream)}", flush=True)
    async with websockets.serve(
        handle_client,
        host,
        port,
        process_request=process_request,
        ping_interval=30,
        ping_timeout=10,
    ):
        await asyncio.Future()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
