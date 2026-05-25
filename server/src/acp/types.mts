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
  sessionId: string;
  acpSessionId: string;
  cwd: string;
  process: import("child_process").ChildProcess;
  agent: string;
  pendingPermission: PendingPermission | null;
  terminals: Map<string, TerminalState>;
  restartCount: number;
  /** ACP session ID of the loaded history session, if any */
  loadedSessionId?: string;
  /** Maps bridge-generated tool call IDs → agent's original toolCallId */
  toolCallIdMap: Map<string, string>;
  /** Latest original toolCallId from agent, used by terminal mapping */
  lastToolCallId?: string;
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
