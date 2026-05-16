# Anywhere — Remote AI Coding Agent Client for HarmonyOS

## ⚠️ Golden Rule: Always use native ArkUI components

Prefer ArkUI built-in components (SideBarContainer, bindSheet, bindMenu, Navigation, etc.) over hand-written overlays, modals, or custom implementations. Native components get free system-level behaviors: animations, accessibility, multirender lifecycle, and OS upgrades. Always wrap state changes in `animateTo()` to ensure smooth transitions — native components animate by default when triggered via their built-in interaction, but programmatic toggles need explicit `animateTo()`.

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
│  └─ Navigation            │────────→│  监听 ws://0.0.0.0:6767  │
│     ├─ OnboardingView     │         │                          │
│     │  (form/connecting/  │         │  ACP Agent (子进程)       │
│     │   discovering/      │         │  ├─ JSON-RPC 2.0          │
│     │   agent picker)     │←───────│  │   over stdio            │
│     └─ NavDestination     │  agent  │  ├─ session/new           │
│        "chat": ChatView   │  event  │  ├─ session/prompt        │
│         (workspace select │         │  ├─ session/set_model     │
│          + session select │         │  └─ session/set_mode      │
│          + ChatPage)      │         └──────────────────────────┘
└───────────────────────────┘
```

**Data flow:** App WS Message → server.js → ACP JSON-RPC → Agent → ACP Response → server.js → WS Message → App renders UI

**ACP protocol:** Agent-agnostic by design. ANY agent implementing ACP (JSON-RPC 2.0 over stdio) works.

## Key Design Decisions

### Visual Design Principles
- **Aesthetic:** Cyber-minimalist, terminal-inspired monospace UI
- **Message Cards:** Full-width blocks with right-side green border (`Colors.accent`) for user, left-side gray border (`Colors.borderLight`) for agent
- **Typography:** Strictly `monospace` throughout for terminal feel
- **Color Palette:** Single green accent + grays, no secondary colors

### Component Implementations

1. **Icons — SymbolGlyph (CRITICAL):**
   - **ALWAYS** use `SymbolGlyph($r('sys.symbol.xxx'))` for icons — NOT SVG files, NOT Unicode characters.
   - `Image` with `$r('app.media.ic_xxx')` is the OLD approach. SymbolGlyph is native, auto-scales, and supports color/fontWeight/effects.
   - **Verified working symbol names:**
     - `sys.symbol.ohos_trash` (trash/delete)
     - `sys.symbol.ohos_wifi` (connection/wifi)
     - `sys.symbol.ohos_folder_badge_plus` (add folder)
     - `sys.symbol.ohos_folder` (folder)
     - `sys.symbol.checkmark` (check/done)
     - `sys.symbol.circle` (circle/empty)
     - `sys.symbol.chevron_down` (dropdown arrow)
     - `sys.symbol.xmark` (close/cancel)
     - `sys.symbol.xmark_circle` (error/fail)
     - `sys.symbol.ellipsis_message_1` (loading/thinking)
     - `sys.symbol.arrow_up_circle_fill` (send)
     - `sys.symbol.paperclip` (attachment)
     - `sys.symbol.mic` (microphone)
     - `sys.symbol.waveform` (waveform)
     - `sys.symbol.clock` (pending/waiting)
     - `sys.symbol.doc` (document/copy)
     - `sys.symbol.AI` (AI/sparkles)
     - `sys.symbol.square` (session indicator)
   - **Names that do NOT exist** (common mistakes): `sparkles`, `terminal`, `gear`, `ellipsis`, `rectangle_fill`, `ohos_command` — verify before use.
   - Full list at: https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

2. **Navigation (Routing):**
   - Uses `Navigation(NavPathStack)` with `navDestination(this.PagesMap)` — a `@Builder` reference, NOT a lambda.
   - The `@Builder PagesMap(name: string)` matches names to `@Component` structs.
   - Each destination must be a `@Component` with `NavDestination()` as root.
   - Home content (OnboardingView) goes inside `Navigation(stack) { ... }` as default child.
   - `NavigationMode.Stack` mode is set explicitly.

3. **State Management (V1 + V2 hybrid + Persistence):**
   - Model classes use `@ObservedV2`/`@Trace` (V2 decorators): `ChatStoreModel`, `WorkspaceStoreModel`, `PlanEntry`.
   - UI components use V1: `@Component`/`@State`/`@Prop`.
   - Global singletons (`ChatStore`, `WorkspaceStore`) are `@ObservedV2` instances.
   - UI state that needs global access (messages, sessions, models, etc.) lives in `ChatStore`.
   - Local UI state (showPathInput, showDrawer) stays as `@State` in the component.
   - **Persistence layer:** `StorageService` wraps `@kit.ArkData` preferences for serverUrl, lastAgent, workspaces.
   - `AppStorage` for cross-component state (`serverUrl`, `lastAgent`, `isConnected`).
   - `@StorageLink('serverUrl')` in OnboardingView for automatic sync with AppStorage.

4. **ChatStore Global State:**
   - `ChatStore.messages` — array of MessageData
   - `ChatStore.planEntries` — array of PlanEntry
   - `ChatStore.turnActive`, `ChatStore.sessionId`, `ChatStore.connected`
   - `ChatStore.sessions`, `ChatStore.models`, `ChatStore.modes`
   - `ChatStore.selectedAgentName`, `ChatStore.agentType`
    - Streaming updates: reassign arrays with `ChatStore.messages = [...ChatStore.messages, newMsg]`
    - **CRITICAL: LazyForEach key for streaming messages MUST be `msg.id + msg.content.length`** — NOT just `msg.id`. During streaming, text appends to the same message (same id, longer content). If the key is only `msg.id`, LazyForEach won't detect the change and won't re-render, so the message gets stuck at truncated text. The `+ msg.content.length` ensures the key changes on each append, forcing re-render. This bug has been introduced by multiple agents independently.

5. **Markdown Rendering:**
   - Uses `@luvi/lv-markdown-in` (v3.4.1, Gitee: `https://gitee.com/luvi/lv-markdown-in.git`).
   - During `turnActive`, agent message chunks render as plain `Text()`. On `turn_ended`, switches to `MarkdownRender`.

6. **Workspace Management:**
   - Managed via inline `Select` dropdown in `ChatView`, not a drawer overlay.
   - Workspace data in `WorkspaceStore` (global `@ObservedV2` singleton).

7. **Auto-Reconnect:**
   - `WSClient` with exponential backoff (1s → 2s → 4s → ... → 30s max).
   - `backgroundTaskManager.requestSuspendDelay()` for ~3min background keepalive.

8. **Animations & Transitions:**
   - View transitions: `TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 }))` with `.animation({ duration: Duration.normal, curve: Curve.EaseOut })`.
   - Message cards: slide-in on appear with `TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))`.
   - Button press feedback: `@State scale` with `.scale({ x: this.scale, y: this.scale })` on `TouchType.Down/Up`.
   - Thinking section expand/collapse: `animateTo()` with `Curve.EaseInOut`.
   - Agent list items: staggered entry with `delay: index * 50`.

## ⚠️ ArkTS Syntax Pitfalls (Critical — Read Before Coding)

### Type System Restrictions
| Rule | What NOT to do | Correct approach |
|------|---------------|-----------------|
| `arkts-no-any-unknown` | `x as unknown as string` | `String(x)` or `Boolean(x)` |
| `arkts-no-typing-with-this` | `this: Type` in function params | Remove `this` param |
| object-to-primitive cast | `params.isUser as boolean` | `Boolean(params['isUser'])` |
| object-to-primitive compare | `params['isUser'] === true` | `Boolean(params['isUser'])` |
| arrow-ts-parameter | `const fn = (x: number) => x` | `const fn = (x: number): number => x` |
| untyped object literals | `const prefs = { key: 'val' }` | Define explicit interface first |

### Navigation API (Most Common Failure)
| Mistake | Wrong | Correct |
|---------|-------|---------|
| navDestination arg type | `.navDestination((name, param) => {})` | Create a `@Builder PagesMap(name: string)` and use `.navDestination(this.PagesMap)` |
| Destination content | Inline `Column() { ... }` | Create a separate `@Component` struct with `NavDestination()` as root |
| param type | `param: unknown` or `param: any` | `param: Object` (but `unknown`/`any` are banned) |

### bindSheet
- `bindSheet($$state, content, options)` — DOES work on a top-level component like `Navigation`.
- Does NOT work when chained inside a `@Builder` function (parser fails with "unexpected token").
- `$$` binding only works with `@State`, NOT `@Prop`.

### SideBarContainer
| Constraint | Explanation |
|-----------|-------------|
| No `if/else` as direct child | Must wrap content in a `@Builder` or `@Component` |
| Only 2 children allowed | Exactly 1 sidebar + 1 content |
| Animation | Built-in slide animation ONLY via `showControlButton(true)`. For programmatic toggle (custom button), use `animateTo({ duration: 300 }, () => { this.showDrawer = val })` AND set `.showSideBar(this.showDrawer)` (NO `$$`). `$$` bypasses animation system. |
| `showSideBar` | Use direct property `.showSideBar(this.showDrawer)` NOT `$$` when you need animation |
| Preferred alternative | Use `Stack` + `position({x:0,y:0}).zIndex(100)` + conditional rendering instead |

### @Reusable + aboutToReuse
- `aboutToReuse(params: Record<string, object>)` — must convert types via `String()` and `Boolean()`, NOT `as` cast.
- `@State` (not `@Prop`) must be used for variables that update on reuse.
- `as unknown as Type` is BANNED — use `String(params['key'])` or `Boolean(params['key'])`.

### Conditional Rendering in NavDestination
- `if (this.stateVar)` conditional inside `NavDestination` may NOT re-render when `@State` changes.
- **Workaround:** Use `Visibility` property instead of conditional `if`:
  ```ets
  Row() { ... }
  .visibility(this.showDrawer ? Visibility.Visible : Visibility.None)
  ```
- This applies specifically to `NavDestination` children, not regular `@Component` structs.

### Text.onClick / Button.onClick
- `Text('\u2630').onClick(...)` — onClick may NOT fire on plain `Text` in some contexts.
- **Always use `Button()` for clickable elements**, or wrap `Text` in a `Row()` with `.onClick()`.

### Input Components
| Component | onSubmit signature | Notes |
|-----------|-------------------|-------|
| `TextInput` | `(value: string, event: SubmitEvent) => void` | ArkTS API |
| `TextArea` | `() => void` or `(EnterKeyType, SubmitEvent)` | Use `enterKeyType(EnterKeyType.Send)` |

### Border Syntax
```ets
// WRONG — won't compile:
.border({ left: { width: 3 } })

// CORRECT:
.border({ width: { left: 3 }, color: { left: Colors.accent } })
```

### Imports
- `import` statements MUST be at the TOP of the file, before any other declarations.
- Circular imports: `A → B → A` causes compiler errors. Break cycles by inlining simple types or creating a shared types file.
- **Single source of truth:** All design tokens imported from `../constants/DesignTokens` (Colors, FontSize, Spacing, Radius, Duration, Shadow all in one file).

### SymbolGlyph Resource Names
- Pattern: `$r('sys.symbol.ohos_xxx')` or `$r('sys.symbol.xxx')`
- **NOT all SF Symbol names work** — many common names like `sparkles`, `terminal`, `gear`, `ellipsis` do NOT exist in HarmonyOS SDK.
- If a symbol name fails with "Unknown resource name", verify at https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/ or use a known working alternative.
- `fontColor` requires an **array**: `fontColor([Colors.accent])`, NOT `fontColor(Colors.accent)`.

### @Provide/@Consume
- `@Provide('key')` in parent, `@Consume('key')` in child — key string must match exactly.
- Alternative: use `AppStorage.setOrCreate()` for simple global state.

### LazyForEach + IDataSource
- `IDataSource` requires explicit `registerDataChangeListener` / `unregisterDataChangeListener` implementations.
- `LazyForEach` key function must return a **unique string** per item (e.g., `msg.id`).
- Data source `updateData()` must call `notifyDataReload()` on all registered listeners.

### @StorageLink
- `@StorageLink('key')` requires the key to be pre-initialized via `AppStorage.setOrCreate()` **before** the component is created.
- Best place: `EntryAbility.onCreate()`.

## Build & Deploy

### USB / 无线部署
```powershell
# Build
cd Anywhere_harmony
node "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p module=entry@default -p product=default assembleHap

# Deploy (device UDID: 2NP0224627054426)
hdc -t 2NP0224627054426 install "entry/build/default/outputs/default/entry-default-signed.hap"
hdc -t 2NP0224627054426 shell aa start -a EntryAbility -b com.anywhere.app
```

### 无线调试（Wi-Fi）
手机和电脑连同一局域网后，在手机开发者选项中开启"无线调试"获取 IP:端口：
```powershell
# 1. 建立 TCP 连接（IP:端口每次可能不同）
hdc tconn 192.168.x.x:xxxxx

# 2. 确认设备已连接
hdc list targets

# 3. 部署 / 启动
hdc install "entry/build/default/outputs/default/entry-default-signed.hap"
hdc shell aa start -a EntryAbility -b com.anywhere.app
```
注意：无线首次连接建议先用 USB 连一次再切无线，更稳定。断线后重新 `hdc tconn` 即可。

### Bridge Server (must be running on PC)

Server is built with `@agentclientprotocol/sdk` (TypeScript).

```powershell
cd Anywhere
npm run build        # Compile TypeScript → server/dist/
npm start            # Start SDK-based server (server/dist/server.mjs)
# OR use fallback:
npm run server:old   # Old hand-written server (keep for rollback)
```

## Current State

### Working
- WebSocket connection to bridge server via manual IP/Port configuration (onboarding form)
- ACP session creation and streaming chat
- Agent auto-discovery + inline agent picker list (after connection)
- Navigation + NavPathStack routing (native HarmonyOS page transitions with OnboardingView as home)
- Terminal-style message blocks with monospace text
- Thinking content + tool call cards + agent message text
- Markdown rendering (tables, code blocks, LaTeX math, links) on turn completion
- Streaming text via plain `Text()` during active turn
- Workspace management (add/select via inline `Select` dropdown)
- Model and Mode selection (`Select` dropdowns)
- Native SymbolGlyph icons (system built-in, no SVG files needed, no Unicode characters)
- Message text copying via system pasteboard
- Session clearing functionality
- Auto-reconnect with exponential backoff
- Background task keepalive (~3min)
- Session list with load/switch via dropdown
- Disabled input during turnActive
- Auto-scroll to bottom on new messages
- Working directory passed via workspace path
- TextArea multi-line input (1-6 lines, Enter to send)
- MessageCard @Reusable component recycling
- ChatStore global state (observable across components)
- **View transition animations** (fade + slide on state changes)
- **Message card entry animations** (slide-in on appear)
- **Button press feedback** (scale animation on touch)
- **LazyForEach** message list with IDataSource (performance optimized)
- **AppStorage persistence** for serverUrl, lastAgent
- **Preferences persistence** via StorageService for serverUrl, lastAgent, workspaces
- **Unified design tokens** (single DesignTokens.ets file, no Colors.ets)
- **Title bar session title** correctly resolved using `loadedSessionId` fallback when loading history sessions
- **Title bar model name** tracks `ChatStore.modelIndex` instead of always showing first model

### Not Working / TODO
- File upload (placeholder)
- Microphone/Voice input (placeholder)
- Permission request dialog
- Session renaming
- Host list management (saving multiple bridge servers)
- Cancel current turn
- Error recovery on message send failure (turn stays active)
- Workspace drawer overlay (broken inside NavDestination — replaced with inline Select)
- bindSheet (doesn't work inside @Builder — agent picker is inline instead)
- Workspace delete (needs UI for deletion)

## File Structure

```
entry/src/main/ets/
├── pages/
│   └── Index.ets                    # Navigation root + PagesMap builder
├── feature/
│   ├── onboarding/
│   │   └── OnboardingView.ets       # NavDestination: connect + agent picker (home)
│   ├── chat/
│   │   ├── ChatPage.ets             # Message list + input bar
│   │   └── ChatInputBar.ets         # TextArea + model/mode selects
│   └── workspace/
│       └── WorkspaceDrawer.ets      # Drawer overlay component
├── components/
│   └── ChatView.ets                 # NavDestination: workspace + session selects
├── common/
│   ├── model/
│   │   ├── ChatState.ets            # ChatStore, ModelItem, ModeItem, PlanEntry
│   │   ├── WorkspaceInfo.ets        # WorkspaceStore, WorkspaceInfo
│   │   ├── MessageData.ets          # MessageData class
│   │   └── AgentConfig.ets          # AgentModel, AgentMode
│   ├── ui/
│   │   ├── MessageCard.ets          # @Reusable message card component
│   │   ├── ThinkingSection.ets      # Thinking content section
│   │   ├── ToolCallCard.ets         # Tool call status card
│   │   ├── PlanView.ets             # Plan entries display
│   │   ├── MarkdownRender.ets       # Markdown rendering wrapper
│   │   ├── CardHeader.ets           # Message card header
│   │   └── MessageDataSource.ets    # IDataSource for LazyForEach
│   └── websocket/
│       ├── WSClient.ets             # WebSocket client with auto-reconnect
│       └── WSProtocol.ets           # Protocol types (ClientMessage, AcpUpdate)
├── services/
│   └── StorageService.ets           # Preferences persistence service
├── constants/
│   └── DesignTokens.ets             # Unified: Colors, Spacing, Radius, FontSize, Shadow, Duration
├── entryability/
│   └── EntryAbility.ets             # App entry, AppStorage initialization
└── entrybackupability/
    └── EntryBackupAbility.ets       # Backup ability
```

## Documentation

- **ACP Protocol Spec:** `docs/acp-protocol.md` — Full 19-chapter reference
- **Frontend Architecture:** `docs/app-frontend-architecture.md`
- **Plans:** `docs/plans/` — Implementation plans and design docs
- **Native Component Improvement Plan:** `docs/plans/2026-05-15-native-component-improvement-plan.md`

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
