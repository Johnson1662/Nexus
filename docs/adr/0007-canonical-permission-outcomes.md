# 7. Canonical Permission Outcomes

Date: 2026-07-29

## Status

Accepted

## Context

In-app and NotificationKit Permission Delegation adapters emitted several local outcome names that did not match either Bridge Server validation or ACP's permission response shape. The request could be displayed but never resolved.

## Decision

Nexus uses two canonical Permission Outcomes: `selected` with the Agent-provided option identifier and `cancelled` without one. The Bridge Server maps that interface directly to ACP. In-app and NotificationKit are adapters at the same Permission Delegation seam and cannot define additional outcome values.

## Consequences

- **Correctness**: each user decision resolves the pending ACP request.
- **Locality**: outcome validation and state transition have one owner.
- **Leverage**: both adapters share one interface and one contract test.
