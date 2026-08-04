# Nexus Domain Model

Nexus is a HarmonyOS-first AI Agent remote control and code collaboration hub, bridging mobile devices with PC-bound AI Agents via the Agent Client Protocol (ACP).

## Language

**Active Session**:
A live AI agent conversation or task currently executing or waiting for input on a host machine.
_Avoid_: Running process, task thread

**Bridge Server**:
The PC-side Node.js daemon that interfaces between mobile WebSocket clients and local ACP agent processes.
_Avoid_: Proxy, server backend

**Session Capture**:
The dual-channel mechanism (ACP API + FS Watcher) for discovering and tracking active sessions on the host machine.
_Avoid_: Process spying, DB polling

**Session Identity**:
The canonical ACP session identifier used to join a Session Capture update to exactly one Active Session. A filesystem activity marker without this identifier is not an Active Session identity.
_Avoid_: Active database label, inferred process key

**Permission Delegation**:
The remote security workflow where PC-side AI Agent execution prompts are intercepted and forwarded to the mobile app for one-tap authorization.
_Avoid_: Remote sudo, shell override

**Permission Outcome**:
The canonical response to a Permission Delegation: `selected` with the Agent-provided option identifier, or `cancelled` without one.
_Avoid_: Allow once, reject once, accept, deny

**Race Probing**:
The parallel network discovery strategy that queries multiple candidate host URLs simultaneously to select the fastest responder.
_Avoid_: Sequential fallback, IP scanning

**File Diff Viewer**:
An integrated feature in the mobile File Browser displaying Git Diffs and edit revision history for workspace files.
_Avoid_: Swipe accept card, standalone review modal

**Host**:
A physical or virtual PC running the Bridge Server and AI Agents.
_Avoid_: Device, machine, server
