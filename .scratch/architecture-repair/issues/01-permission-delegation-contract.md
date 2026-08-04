# 01 — Repair Permission Delegation contract

**What to build:** A mobile approval, dismissal, or notification action completes the same Active Session permission request with an ACP-valid outcome.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] Selecting a permission option sends `selected` with its option identifier and resolves the ACP request.
- [ ] Dismissing or rejecting sends `cancelled` and resolves the ACP request.
- [ ] Foreground and NotificationKit adapters use the same outcome contract.
- [ ] A server contract test rejects malformed outcomes and accepts both canonical outcomes.
