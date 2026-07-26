# 01 — Deep SessionManager Core Module & Process Pool

**What to build:**
Create the `SessionManager` deep class in `server/src/session-manager.mts` that encapsulates session state storage, ACP process spawning, LRU eviction, process pool management, and sliding inactivity timeouts behind a small interface.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Create `SessionManager` class with `AcpClientFactory` DI interface
- [ ] Encapsulate process pool (MAX 5 ACP processes) and 15-minute idle timeout logic
- [ ] Move sliding prompt inactivity timeout (5 mins) and `MODEL_ERROR_PATTERNS` inside `SessionManager.dispatchPrompt`
- [ ] Provide `getOrCreate()`, `dispatchPrompt()`, `replayBuffer()`, `evictIdle()`, and `close()`
- [ ] Write unit tests for `SessionManager` using mock client factory
