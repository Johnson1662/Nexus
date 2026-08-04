# Nexus Active Session Repair Specification

## Problem Statement

Nexus Permission Delegation cannot complete: mobile approval outcomes do not match the Bridge Server contract or ACP contract. Session Capture also emits identities that cannot be joined to Active Sessions, while SessionManager still shares ownership with a legacy session module. Flutter discards activity timestamps, and session titles do not persist remotely.

## Solution

Repair the end-to-end Permission Delegation contract; make Session Capture publish only canonical Active Session identities; make SessionManager the single session owner; retain session activity in the mobile projection; and persist remote session titles by Host.

## User Stories

1. As a mobile user, I want selecting a permission option to continue the Active Session so that an Agent can safely proceed.
2. As a mobile user, I want dismissing an approval request to cancel it so that no operation is implicitly authorized.
3. As a mobile user, I want notification actions to follow the same Permission Delegation contract as the in-app sheet.
4. As a mobile user, I want live Active Session status to attach to the correct session so that I know which Agent is running.
5. As a mobile user, I want recent sessions ordered by actual activity so that the most relevant work is visible.
6. As a mobile user, I want renamed session titles to survive Bridge Server restart so that organization remains intact.
7. As a maintainer, I want one SessionManager owner so that reconnect, buffering, cleanup, and ACP callbacks have locality.
8. As a maintainer, I want contract tests at the Permission Delegation and Session Capture seams so that protocol drift fails deterministically.

## Implementation Decisions

- Permission Delegation exposes canonical outcomes only: `selected` with an option identifier, or `cancelled` without one. The Bridge Server maps that interface directly to the ACP implementation shape.
- The in-app adapter and NotificationKit adapter are the two real adapters at the Permission Delegation seam. Both submit canonical outcomes through the same module path.
- SessionManager owns all in-memory Active Session state, message buffering, reclaim, cleanup, process teardown, and callback lookup. The legacy duplicate map is removed after all callers move.
- Session Capture joins only canonical ACP session identities. Unidentified filesystem activity is not misattributed to an Active Session. Live SessionManager activity remains a canonical source.
- The Flutter Active Session projection retains `lastActivity`; status deltas patch only changed fields and recency ordering uses that value.
- Remote session titles are stored by the Bridge Server in its Nexus state directory and applied to every Session Capture listing.

## Testing Decisions

- Test externally visible protocol behavior, never private maps or callback bodies.
- Server contract tests cover selected and cancelled Permission Delegation outcomes, canonical Session Capture status payloads, title persistence, and SessionManager ownership paths.
- Flutter tests cover protocol decoding and activity-preserving session projection.
- Existing `server/test-session-watcher.mjs` is prior art for deterministic server seams; existing Flutter widget testing is prior art for Dart execution.

## Out of Scope

- Inferring individual ACP session identities from opaque agent database files.
- Push Kit background wake-up, multi-Agent orchestration UI, and new agent discovery.

## Further Notes

Source evidence: ACP accepts `cancelled` or `selected` with `optionId`; existing mobile outcomes and Bridge Server validation are incompatible. File activity without a resolvable ACP session identity is intentionally not attached to an Active Session.
