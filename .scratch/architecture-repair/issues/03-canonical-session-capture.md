# 03 — Publish canonical Session Capture status

**What to build:** Session Capture status updates attach only to canonical Active Session identities, while unresolvable filesystem activity cannot overwrite an unrelated session.

**Blocked by:** 02 — Make SessionManager the single Active Session owner.

**Status:** ready-for-agent

- [ ] Live Active Sessions publish status with their actual ACP session identifiers.
- [ ] Filesystem statuses merge only when their identifier is canonical.
- [ ] The status broadcast matches its tested production payload.
- [ ] A deterministic test proves an unrelated static filesystem identity cannot alter an ACP session.
