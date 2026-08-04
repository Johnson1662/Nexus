# 04 — Preserve Active Session activity on mobile

**What to build:** The mobile Active Session projection retains status activity timestamps and uses them for session recency without losing existing metadata.

**Blocked by:** 03 — Publish canonical Session Capture status.

**Status:** ready-for-agent

- [ ] Status updates retain last activity and existing session metadata.
- [ ] Recent session ordering uses activity after pinned and active precedence.
- [ ] A Dart test locks down the projection behavior.
