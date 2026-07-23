# Technical Specification: Nexus AI Agent Remote Collaboration Hub

## Problem Statement

Developers using PC-based AI Coding Agents (such as OpenCode, Claude Code, or Codex) face severe friction when stepping away from their primary workstation. They cannot monitor active agent execution, inspect real-time progress or tool calls, review code modifications, or grant required security permissions from mobile devices. This "black box" execution forces developers to stay tethered to their desks or risk halted or unmonitored agent tasks.

## Solution

Nexus provides a HarmonyOS-first mobile control and collaboration hub. Via a lightweight PC Bridge Server using the Agent Client Protocol (ACP), Nexus bridges mobile devices to PC-bound AI Agents. Developers can monitor active sessions, view real-time thinking and tool execution streams, review workspace file Diffs and edit history inside an integrated file browser, and approve or reject sensitive remote execution permissions—all with a minimal, monochrome aesthetic designed for high touch efficiency.

## User Stories

1. As a developer away from my desk, I want to see a list of active sessions running on my PC, so that I can track background AI tasks in real time.
2. As a mobile developer, I want Nexus to automatically probe and select the fastest available host connection (LAN, hotspot, or Tailscale), so that network switching happens with zero friction.
3. As a developer monitoring an active AI task, I want to see real-time streaming thinking processes and tool execution outputs, so that I can verify the AI's reasoning chain.
4. As a user reviewing code changes, I want to view Git Diffs and edit history inside the mobile File Browser, so that I can inspect workspace modifications without interrupting my active chat.
5. As a developer, I want a minimalist typing indicator at the end of the AI's response stream, so that I have immediate visual feedback when the AI agent is actively working.
6. As a security-conscious user, I want remote permission requests (such as package installation or shell execution) to trigger an approval card on my mobile app, so that I can safely authorize or deny high-risk actions.
7. As a mobile user, I want host machines to be identified by their human-readable hostnames rather than technical UUIDs, so that I can easily recognize my workstation.
8. As a developer switching between multiple host IP addresses, I want Nexus to merge candidate IPs under a single host entry, so that I don't see duplicate host cards.
9. As a user opening the app, I want the UI to render immediately without waiting for network probing, so that I never experience a blank startup screen.
10. As a developer navigating projects, I want a flat, high-whitespace project list with clear folder and chat icons, so that I can quickly jump to specific workspaces.
11. As a mobile user, I want an expandable action sheet from the input bar, so that I can easily attach photos, switch to plan mode, or invoke plugins.
12. As a developer, I want all sensitive network connection errors to be caught gracefully and formatted cleanly, so that the mobile application never crashes during connectivity loss.

## Implementation Decisions

### 1. Dual-Channel Session Capture Architecture (ADR 0001)
- The PC Bridge Server discovers active sessions using a primary ACP `session/list` API query supplemented by an asynchronous file-system watcher (monitoring `~/.claude/sessions` and `~/.opencode`).
- Session states are normalized into unified records containing `sessionId`, `agentName`, `cwd`, and `status` (`running`, `waiting_input`, `idle`, `error`).

### 2. Parallel Race Host Probing (ADR 0002)
- Mobile connectivity uses a parallel race probing algorithm (`connectBest`). Upon network changes, Nexus queries all candidate host URLs (LAN, hotspot, Tailscale, Relay) simultaneously via HTTP `/probe` requests.
- The first endpoint returning HTTP 200 is selected for WebSocket connection, canceling remaining pending probes.

### 3. Integrated File Browser Git Diff & Edit History Review (ADR 0003)
- Code review is integrated directly into the mobile File Browser panel (`_buildFileOverlay`).
- Selecting a file displays unified Git Diffs and historical revision entries without blocking the main conversational flow.

### 4. Out-of-Band Remote Permission Delegation (ADR 0004)
- PC-side AI Agent execution prompts (e.g., shell commands, package installations) trigger `permission_request` events over ACP.
- The Bridge Server forwards these prompts to the mobile app, where a dedicated approval card allows one-tap remote authorization or rejection.

### 5. Brand Identity & UI Design Language
- App rebranded to **Nexus** across all multilingual resources (`zh_CN`, `en_US`, `AppScope`).
- Icon design: Pure white squircle canvas featuring a 3D Isometric ASCII Wireframe Block "N" monogram (`nexus_3d_ascii_n.svg`).
- Aesthetic: Strict monochrome black-grey-white color palette, zero heavy Card shadows, high-whitespace flat list rows.

## Testing Decisions

### 1. Testing Philosophy
- Tests must verify observable external behavior and contracts rather than internal implementation details or private widget states.
- Mocking is restricted to external network sockets and process IPC boundaries.

### 2. Tested Seams
- **PC-Side Protocol Seam**: Verifies that the Bridge Server accurately transforms ACP Agent events (`session/list`, `permission_request`, `agent_thought_chunk`) into valid WebSocket client payloads (`session_status_update`, `permission_request`).
- **Mobile State & Connectivity Seam**: Verifies that the Mobile state provider correctly consumes WebSocket messages, transitions session phases, triggers `connectBest` parallel probing, and handles network disconnections without throwing uncaught exceptions.

### 3. Prior Art
- PC Server handlers (`server/src/handlers/`) test JSON-RPC payload serialization against mock ACP streams.
- Mobile client unit/widget tests verify state mutations and fallback UI handling under mock WebSocket events.

## Out of Scope

- Direct editing of remote source code files inside the mobile app (mobile app is for review, chat, and control, not heavy code authoring).
- Running local AI model inference directly on the mobile device (inference remains offloaded to PC-side AI Agents).
- Native iOS client implementation (current target is HarmonyOS / Flutter-OHOS).

## Further Notes

- Competition Submission Alignment: The Nexus architecture aligns directly with the "Agent Innovation" track of the 2026 China University Computer Contest - AI Creative Competition (HarmonyOS Track), emphasizing ACP protocol integration, dual-channel session capture, and out-of-band security delegation.
