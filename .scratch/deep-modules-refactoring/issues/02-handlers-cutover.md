# 02 — Protocol Handlers Cutover to SessionManager

**What to build:**
Refactor server protocol handlers (`start.mts`, `load-session.mts`, `input.mts`, `cancel.mts`, `close-session.mts`, `set-config.mts`, `switch-model.mts`) to delegate to `SessionManager`, removing direct state mutations of `sess.turnActive`, `sess.orphanedAt`, and `sess.ws`.

**Blocked by:** 01 — Deep SessionManager Core Module & Process Pool

**Status:** ready-for-agent

- [ ] Refactor `start.mts` to use `sessionManager.getOrCreate()`
- [ ] Refactor `load-session.mts` and `resume-session.mts` to use `sessionManager.getOrCreate()` and `sessionManager.replayBuffer()`
- [ ] Refactor `input.mts` to use `sessionManager.dispatchPrompt()`
- [ ] Refactor `cancel.mts` and `close-session.mts` to use `sessionManager.cancel()` and `sessionManager.close()`
- [ ] Ensure all handler files are thin 3-line adapters with zero direct session map mutations
