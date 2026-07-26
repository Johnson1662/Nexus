# Spec: Deep Modules Architecture Refactoring (SessionManager, AgentRegistryService, SessionStatusWatcher)

## Problem Statement

As Nexus grows to support dozens of concurrent AI agents, multi-session background processing, and real-time status updates, the server codebase suffers from architectural friction:

1. **Scattered Session Lifecycle (`server/src/session.mts` & Handlers)**: Session state mutations (`turnActive`, `orphanedAt`, `resetTimeout`, `pendingPermission`) and process spawning/callback wiring are fragmented across 8+ shallow protocol handlers (`start.mts`, `load-session.mts`, `input.mts`, `cancel.mts`, `close-session.mts`).
2. **Coupled Agent Aggregation (`server/src/handlers/list-sessions.mts`)**: Multi-agent temp-client spawning, Promise.race timeouts, path normalization, and custom command resolution are mixed directly inside the WebSocket message handler.
3. **Flat Watcher Module (`server/src/discovery/session-watcher.mts`)**: Disk path rules, process scraping heuristics, interval timers, diff calculations, and global state variables are entangled in a flat file with dead code.

Developer maintainers find it difficult to test logic past the protocol boundary without spinning up full WebSocket servers and real Agent processes.

## Solution

Refactor the PC Bridge Server by introducing three **Deep Modules** behind clean, minimal seams:

1. **Deep `SessionManager`**: Consolidate session lifecycle, process pooling, LRU eviction, sliding inactivity timeouts, prompt dispatching, and event buffer replay into a single deep class (`SessionManager`) with DI via `AcpClientFactory`. Shallow protocol handlers shrink to thin 3-line adapters.
2. **Deep `AgentRegistryService`**: Encapsulate agent discovery, custom command resolution, concurrent temp client querying, path normalization, and timeout safety behind a clean interface method (`agentRegistry.queryAggregateSessions(cwd)`).
3. **Deep `SessionStatusWatcher`**: Extract a class-based `SessionStatusWatcher` with pure diff calculations (`computeSessionDiff`), clean event subscriptions (`onStatusUpdate`), and single-shot scanning (`scanOnce()`). Remove dead process-scraping code.

## User Stories

1. As a server developer, I want session process pooling, LRU eviction, and inactivity timeouts hidden inside `SessionManager`, so that protocol handlers don't leak implementation details.
2. As a server developer, I want to unit test prompt dispatching, model error handling, and message buffering using a `MockAcpClientFactory` without spawning real child processes.
3. As a server developer, I want `AgentRegistryService` to handle multi-agent querying and path normalization, so that `list_sessions` protocol handler is simple and bug-free.
4. As a server developer, I want `SessionStatusWatcher` to expose pure diff functions and event subscriptions, so that I can unit test status diffing without real filesystem timers.
5. As a mobile user, I want all session operations to remain 100% backward-compatible and fast, with zero degradation in performance or reliability.

## Implementation Decisions

- **SessionManager Seam & Interface**:
  - Expose `getOrCreate(ws, params)`, `dispatchPrompt(sessionId, text)`, `replayBuffer(sessionId, lastMessageId)`, `evictIdle()`, `close(sessionId)`.
  - Move `MODEL_ERROR_PATTERNS` and `resetInactivityTimer` inside `SessionManager.dispatchPrompt()`.
  - Eliminate direct mutations of `sess.turnActive`, `sess.orphanedAt`, and `sess.ws` outside of `SessionManager`.

- **AgentRegistryService Seam & Interface**:
  - Expose `listInstalledAgents()`, `queryAggregateSessions(cwd)`, `installAgent(agentId)`, `uninstallAgent(agentId)`.
  - Perform `path.resolve(cwd).toLowerCase()` normalization inside `queryAggregateSessions`.
  - Enforce 12-second timeout safety per agent query.

- **SessionStatusWatcher Seam & Interface**:
  - Class `SessionStatusWatcher` with `start()`, `stop()`, `scanOnce()`, and `onStatusUpdate(listener)`.
  - Pure function `computeSessionDiff(prev, curr)` for deterministic diffing.
  - Remove dead `enrichWithProcessStatus` subprocess execution.

## Testing Decisions

- **Seam 1: SessionManager Unit Seam**:
  - Test via `SessionManager` instance with `MockAcpClientFactory`.
  - Verify process pool limits, LRU eviction, sliding inactivity timeouts, and message buffer replays without real child processes.
- **Seam 2: AgentRegistryService Aggregation Seam**:
  - Test `queryAggregateSessions(cwd)` with mock agent list.
  - Verify path normalization and timeout resilience.
- **Seam 3: SessionStatusWatcher Seam**:
  - Test `computeSessionDiff` pure function with array snapshots.
  - Test `scanOnce()` against mock local directories.

## Out of Scope

- Refactoring Flutter UI widgets (Flutter UI refactoring is complete).
- Modifying the underlying ACP protocol JSON-RPC spec.

## Further Notes

- Includes creating ADR 0005 (`docs/adr/0005-deep-session-and-agent-registry-architecture.md`).
- All changes must pass `npm run build` and `test-session-watcher.mjs`.
