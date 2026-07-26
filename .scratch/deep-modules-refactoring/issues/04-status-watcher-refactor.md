# 04 — Deep SessionStatusWatcher Class & Pure Diff Engine

**What to build:**
Refactor `server/src/discovery/session-watcher.mts` into a class-based `SessionStatusWatcher` module. Extract pure `computeSessionDiff(prev, curr)` function, eliminate dead `enrichWithProcessStatus` subprocess code, and expose clean event listener subscriptions.

**Blocked by:** 03 — Deep AgentRegistryService Module & List Sessions Simplification

**Status:** ready-for-agent

- [ ] Extract pure `computeSessionDiff` function for deterministic diff testing
- [ ] Create `SessionStatusWatcher` class with `start()`, `stop()`, `scanOnce()`, and `onStatusUpdate(listener)`
- [ ] Remove dead process-scraping code (`enrichWithProcessStatus`)
- [ ] Update `server.mts` to consume `SessionStatusWatcher`
- [ ] Update `test-session-watcher.mjs` test suite to verify all assertions pass cleanly
