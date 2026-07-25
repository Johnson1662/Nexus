export interface PendingPermission {
  requestId: string;
  resolve: (value: any) => void;
}

export interface TerminalExitStatus {
  exitCode: number | null;
  signal: string | null;
}

export interface TerminalState {
  id: string;
  process: import("child_process").ChildProcess;
  output: string;
  truncated: boolean;
  exitStatus: TerminalExitStatus | null;
  exitPromise: Promise<void>;
  resolveExit: (() => void) | null;
  outputByteLimit: number;
}

export interface SessionState {
  ws: import("ws").WebSocket;
  client: import("./client.mjs").AcpClient;
  /** Canonical ACP Agent session identifier (ses_... or UUID) — single key throughout the stack */
  sessionId: string;
  cwd: string;
  process: import("child_process").ChildProcess;
  agent: string;
  pendingPermission: PendingPermission | null;
  terminals: Map<string, TerminalState>;
  restartCount: number;
  /** Maps bridge-generated tool call IDs → agent's original toolCallId */
  toolCallIdMap: Map<string, string>;
  /** Latest original toolCallId from agent, used by terminal mapping */
  lastToolCallId?: string;
  /** Whether this session currently has an active turn in progress */
  turnActive: boolean;
  /** Optional callback to reset the prompt inactivity timeout on new output/tool activity */
  resetTimeout?: () => void;
  /** Timestamp of last session activity (input, output, or interaction) */
  lastActivity: number;
  /** Timestamp when session was orphaned (WS disconnected), null if active */
  orphanedAt: number | null;
  /** Buffered messages for cursor sync replay (Phase 3a) */
  messageBuffer: Array<{ messageId: string; payload: string; timestamp: number }>;
}

export interface WSClientMessage {
  type: string;
  sessionId?: string;
  text?: string;
  agent?: string;
  prompt?: string;
  cwd?: string;
  model?: string;
  modeId?: string;
  requestId?: string;
  outcome?: string;
  optionId?: string;
}

export interface WSServerMessage {
  type: string;
  sessionId?: string;
  [key: string]: any;
}
