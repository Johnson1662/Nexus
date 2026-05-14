# Anywhere — Remote AI Coding Agent Client for HarmonyOS

## ⚠️ CRITICAL: Always Use huawei-docs MCP

**Before writing ANY HarmonyOS/ArkTS code, you MUST use the `huawei-docs` MCP tools to look up the official API.** Never guess ArkTS API signatures, decorator behavior, or component names. The `huawei-docs_get_page`, `huawei-docs_search_docs`, and `huawei-docs_get_category` tools provide direct access to developer.huawei.com official docs.

This project was built by consulting these docs extensively. Breaking this rule = code that doesn't compile.

## Project Overview

Anywhere is a HarmonyOS App that connects to any ACP (Agent Client Protocol) compatible AI coding agent running on a remote machine via WebSocket. It functions as a mobile developer workspace, bridging your phone to a remote coding environment.

**Architecture:**

```
Phone (HarmonyOS ArkTS App)             PC (Node.js Bridge)
┌───────────────────────────┐          ┌──────────────────────────┐
│  Index.ets (@Entry)       │    WS    │  server.js               │
│  ├─ connecting view       │────────→│  监听 ws://0.0.0.0:6767  │
│  ├─ disconnected/onboard  │         │                          │
│  ├─ workspace select      │         │  ACP Agent (子进程)       │
│  └─ chat view             │←───────│  ├─ JSON-RPC 2.0          │
│      ├─ MessageCard[]     │  agent  │  │   over stdio           │
│      ├─ PlanView          │  event  │  ├─ session/new          │
│      ├─ ChatInputBar      │         │  ├─ session/prompt       │
│         ├─ TextInput      │         │  ├─ session/set_model    │
│         ├─ [Model ▼]      │         │  └─ session/set_mode     │
│         └─ [Mode ▼] Send  │         └──────────────────────────┘
└───────────────────────────┘
```

**Data flow:** App WS Message → server.js → ACP JSON-RPC → Agent → ACP Response → server.js → WS Message → App renders UI

**ACP protocol:** Agent-agnostic by design. ANY agent implementing ACP (JSON-RPC 2.0 over stdio) works.

## Key Design Decisions (The "Terminal" Aesthetic)

The UI has undergone a massive architectural shift from a generic "chat messenger" to a **Developer Workspace / Terminal Console**.

### Visual Design Principles
- **Aesthetic:** Cyber-minimalist, structural, precision-driven.
- **Message Cards:** Replaced traditional rounded "chat bubbles" with full-width structural blocks. User commands are highlighted with a right-side green border (`Colors.accent`), while agent responses have a left-side gray border (`Colors.borderLight`).
- **Typography:** System font (HarmonyOS Sans) for body text, but strictly `monospace` for headers, metadata, terminal paths, and UI component labels to reinforce the coding environment feel.
- **Identity Tags:** Instead of generic "User/Assistant" labels, headers use terminal-style prompts: `user@local ~$` and `agent@remote ~$`.
- **Empty States:** Displays "Anywhere Workspace" and "Agent Client Protocol (ACP) Active" instead of generic chat placeholders.
- **Safe Area:** Bottom input padding is strictly bound to `84px` to avoid occlusion by the phone's bottom gesture bar and rounded corners.

### Component Implementations

1. **Icons (CRITICAL):**
   - **Do NOT use `Path().commands(...)` with absolute pixel values in ArkUI.** It fails to auto-scale on high-density displays (resulting in 2x2 px dots).
   - **ALWAYS** use `<svg>` files placed in `resources/base/media` and loaded via `Image($r('app.media.ic_name')).fillColor(...)`. This ensures crisp, `vp` (virtual pixel) based scaling across all devices.
   - All interactive icons now have actual functions (e.g., Copy icon uses `@ohos.pasteboard`, Clear icon wipes the session, top bar icons invoke `getUIContext().getPromptAction().openToast()`).

2. **Onboarding / Connection Screen:**
   - Pure "ACP Bridge Configuration" form with `IP:Port` (WebSocket URL) input and Connect button.
   - After connecting, `list_agents` is sent to server → server scans PATH for ~55 hardcoded ACP agent binaries → returns list → user picks one → session starts.
   - No manual agent type input needed.

3. **Markdown Rendering:**
   - Uses `@luvi/lv-markdown-in` (v3.4.1, Gitee: `https://gitee.com/luvi/lv-markdown-in.git`) for rendering tables, code blocks, LaTeX formulas, links.
   - **Streaming fallback:** During `turnActive`, agent message chunks render as plain `Text()` to avoid flickering. On `turn_ended`, switches to `MarkdownRender` for full rich rendering.
   - Math formulas enabled via `@cangjie-tpc/formula_hybrid@1.2.7`.

4. **State Management (V1 @Component + @State + @Prop):**
   - We use V1 `@Component`/`@State`/`@Prop` pattern, NOT `@ComponentV2`/`@ObservedV2` (V2 decorators caused reactivity issues with ForEach).
   - **Streaming Updates:** `@State` arrays MUST be re-assigned with new references (e.g., `this.messages = [...this.messages]`) to trigger reactivity. `ForEach` keys must include content length (e.g., `msg.id + msg.content.length`) to force re-rendering during token-by-token streaming.

5. **ACP Data Structure (FLAT):**
   - The ACP `session/update` notification has a **flat** structure. The `sessionUpdate` field IS the type string directly (e.g., `"sessionUpdate": "agent_message_chunk"`). It is NOT nested inside an `event` object.

6. **Server Configuration (Dynamic Spawning):**
   - The bridge server (`server.js`) no longer hardcodes the path to a specific agent's binary. Instead, it dynamically interprets the `agent` parameter received from the client app's connection form (e.g., `opencode` or `claude-code`). It utilizes Node's `child_process.spawn` with `shell: true` to invoke the specified agent directly from the system's `PATH`. This enables true "plug-and-play" ACP-agnosticism.

7. **Agent Discovery:**
   - `server.js` has a hardcoded list of ~55 known ACP agents (from https://agentclientprotocol.com/get-started/agents).
   - On `list_agents` request, scans each binary name in system PATH using `fs.existsSync`.
   - Returns discovered agents to the app for user selection.

8. **Auto-Reconnect:**
   - `WSClient` implements automatic reconnection with exponential backoff (1s → 2s → 4s → ... → 30s max).
   - Uses `backgroundTaskManager.requestSuspendDelay()` for ~3min background keepalive.
   - `intentionalClose` flag prevents reconnect when user explicitly disconnects.
   - Reconnect is silent (no error message) when already in an active session.

9. **Performance Optimizations:**
   - MCP config loading is non-blocking: session created without MCP servers first, then loaded in background.
   - Session list caching (30s TTL) with background async fetch—returns empty immediately then updates.
   - All `showToast()` calls migrated to `getUIContext().getPromptAction().openToast()` (non-deprecated API).

### Known Compilation Notes

- `Text.fontColor()` not `.color()` — ArkTS API
- `LoadingProgress.color()` not `.fontColor()`
- `Button.backgroundColor()` + `.fontColor()` not `.color()`
- `Select` doesn't support `fontSize` — keep defaults
- `@Builder` inside `@Component` can't have variable declarations
- **Border Syntax:** `border({ left: { width: 3 } })` is invalid syntax. The correct, strongly-typed format is `border({ width: { left: 3 }, color: { left: ... } })`.

## Build & Deploy

```powershell
# Build
cd Anywhere_harmony
node "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default assembleHap

# Deploy (device UDID: 2NP0224627054426)
hdc -t 2NP0224627054426 install "entry/build/default/outputs/default/entry-default-signed.hap"
hdc -t 2NP0224627054426 shell aa start -a EntryAbility -b com.anywhere.app
```

### Bridge Server (must be running on PC)
```powershell
cd Anywhere
node server.js
```

## Current State

### Working
- WebSocket connection to bridge server via manual IP/Port configuration
- ACP session creation and streaming chat
- Agent auto-discovery: server scans PATH for 55+ known ACP agents, app shows picker
- Terminal-style message blocks with `user@local` and `agent@remote` headers
- Thinking content (folded by default) + tool call cards + agent message text
- Markdown rendering (tables, code blocks, LaTeX math, links) on turn completion
- Streaming text via plain `Text()` during active turn (no flickering)
- Workspace management (add/select/delete via drawer)
- Model and Mode lists (fetched after session_started)
- Native SVG scaling using `Image` component and local resource files
- Message text copying via system pasteboard (`ic_copy.svg`)
- Session clearing functionality (`ic_clear.svg`)
- Auto-reconnect with exponential backoff (silent for active sessions)
- Background task keepalive (~3min)
- Session list caching (30s) + background async load
- MCP config loaded asynchronously (non-blocking session creation)
- Disabled input during turnActive

### Not Working / TODO
- File upload (Toast placeholder currently bound to `ic_attachment.svg`)
- Microphone/Voice input (Toast placeholder currently bound to `ic_mic.svg`)
- Permission request dialog (Allow/Deny)
- Session renaming
- Host list management (saving multiple bridge servers)
- Cancel current turn
- Error recovery on message send failure (turn stays active)
- Scrolling to bottom on new messages

## Documentation

- **ACP Protocol Spec:** `docs/acp-protocol.md` — Full 19-chapter reference based on official docs
- **Frontend Architecture:** `docs/app-frontend-architecture.md`
- **Plans:** `docs/plans/` — Implementation plans and design docs

## API Reference

### WebSocket Protocol (Client → Server)

| type | fields | trigger |
|------|--------|---------|
| `start` | `agent`, `prompt?`, `cwd?`, `model?` | Connect / new session / first message |
| `input` | `sessionId`, `text` | Send message in existing session |
| `list_agents` | — | After WebSocket connects (auto) |
| `list_models` | — | After `session_started` |
| `list_sessions` | `cwd` | After workspace selected |
| `switch_model` | `sessionId`, `model` | Model select change |
| `set_mode` | `sessionId`, `modeId` | Mode select change |
| `load_session` | `sessionId`, `cwd` | Load history session |

### WebSocket Protocol (Server → Client)

| type | fields | purpose |
|------|--------|---------|
| `session_started` | `sessionId`, `agent` | Session created |
| `agent_event` | `event: AcpUpdate` | Stream chunk (thought/message/tool/plan) |
| `turn_ended` | `stopReason` | Turn complete |
| `agent_list` | `agents[]` | Discovered ACP agents |
| `model_list` | `models[]`, `modes[]` | Available models/modes |
| `session_list` | `sessions[]` | Workspace sessions |

### AcpUpdate.sessionUpdate types

| value | renders as | key fields |
|-------|-----------|------------|
| `agent_message_chunk` | MessageCard text (streaming: Text, done: MarkdownRender) | `content.text` |
| `agent_thought_chunk` | ThinkingSection | `content.text` |
| `tool_call` | ToolCallCard | `toolCallId`, `title` |
| `tool_call_update` | ToolCallCard update | `toolCallId`, `status` |
| `plan` | PlanView | `entries[]` |
| `user_message_chunk` | MessageCard user | `content.text` |
