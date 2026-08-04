# 6. Canonical Session Identity for Session Capture

Date: 2026-07-29

## Status

Accepted

## Context

Session Capture combines ACP discovery with filesystem activity. The filesystem watcher emitted labels such as `opencode-active`, while ACP discovery and Active Sessions use ACP session identifiers. Merging by those unrelated values silently left status updates detached from the intended Active Session.

## Decision

Only an ACP session identifier is a Session Identity. Session Capture may use filesystem activity to enrich a session only when that activity already carries a canonical Session Identity. Unresolvable filesystem markers remain diagnostic input and must not be published as an Active Session status update.

SessionManager publishes status for its own canonical Active Sessions. The watcher may publish external sessions only when their identifiers are canonical.

## Consequences

- **Correctness**: no static filesystem label can overwrite an unrelated Active Session.
- **Locality**: Session Identity joining sits in Session Capture rather than Flutter display code.
- **Leverage**: list and push updates share one identity rule and one test surface.
- **Trade-off**: opaque agent databases do not produce per-session live status until their format exposes an ACP identifier.
