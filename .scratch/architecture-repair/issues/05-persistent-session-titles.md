# 05 — Persist remote session titles

**What to build:** Renaming an Active Session updates the Bridge Server title store and survives a restart/list refresh.

**Blocked by:** 02 — Make SessionManager the single Active Session owner.

**Status:** ready-for-agent

- [ ] Mobile rename requests reach the Bridge Server.
- [ ] Session Capture listings apply the persisted title.
- [ ] Title storage is scoped to the Bridge Server’s Nexus state.
- [ ] A server test verifies set, reload, and list behavior.
