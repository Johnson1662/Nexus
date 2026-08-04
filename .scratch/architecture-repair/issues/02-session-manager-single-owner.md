# 02 — Make SessionManager the single Active Session owner

**What to build:** Reconnect, event replay, callback lookup, process cleanup, and tool-call trimming use one SessionManager module with no duplicate in-memory session registry.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The Bridge Server has no production import of the legacy session registry.
- [ ] ACP callbacks obtain their session runtime through SessionManager.
- [ ] Reconnect and sync preserve the existing observable behavior.
- [ ] A focused server test exercises the migrated ownership seam.
