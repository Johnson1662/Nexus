# 5. Deep Session & Agent Registry Architecture

Date: 2026-07-25

## Status

Accepted

## Context

As Nexus expanded to support multi-agent dynamic discovery, background process retention, sliding prompt inactivity timeouts, and incremental event buffer replay, server-side session logic became scattered across 8+ shallow protocol handlers (`start.mts`, `load-session.mts`, `input.mts`, `cancel.mts`, `close-session.mts`). Direct state mutations of `sess.turnActive`, `sess.orphanedAt`, and `sess.ws` were duplicated across call sites. Furthermore, `list-sessions.mts` and `session-watcher.mts` mixed transport serialization, path normalization, and timer management with global state.

## Decision

We restructure the PC Bridge Server around three **Deep Modules** with minimal interfaces and testable seams:

1. **`SessionManager` (`server/src/session-manager.mts`)**:
   - Single point of truth for session lifecycle, process pooling (max 5 ACP processes), 15-minute idle eviction, sliding prompt inactivity timeouts (5 mins), model error detection, and message buffer replay.
   - Handlers shrink to thin adapters delegating to `sessionManager.getOrCreate()`, `sessionManager.dispatchPrompt()`, and `sessionManager.replayBuffer()`.
   - Dependency injection seam via `AcpClientFactory` allows in-memory unit testing without launching real Agent processes.

2. **`AgentRegistryService` (`server/src/agent-registry-service.mts`)**:
   - Single owner of installed agent discovery, custom command resolution, concurrent temp client querying, 12-second timeout protection, and Windows path normalization (`path.resolve(cwd).toLowerCase()`).
   - `list-sessions.mts` and `list-models.mts` delegate directly to `agentRegistry.queryAggregateSessions(cwd)`.

3. **`SessionStatusWatcher` (`server/src/discovery/session-watcher.mts`)**:
   - Class-based status engine exposing `start()`, `stop()`, `scanOnce()`, and `onStatusUpdate(listener)`.
   - Pure function `computeSessionDiff(prev, curr)` extracted for deterministic diff testing.
   - Dead `enrichWithProcessStatus` subprocess code removed.

## Consequences

- **Leverage**: All session lifecycle rules, process eviction limits, and inactivity timeouts are written once and reused across all protocol handlers. Handlers shrink by ~300 lines.
- **Locality**: Maintainers debug session state, buffer replays, and prompt timeouts in one deep class rather than chasing scattered mutations across 8 files.
- **Testability**: Unit tests run past the interface seam using `AcpClientFactory` and mock filesystem providers without requiring real WebSocket servers or external CLI binaries.
