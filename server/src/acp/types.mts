export interface PendingPermission {
  requestId: string;
  resolve: (value: any) => void;
}

export interface SessionState {
  ws: import("ws").WebSocket;
  client: import("./client.mjs").AcpClient;
  sessionId: string;
  acpSessionId: string;
  process: import("child_process").ChildProcess;
  agent: string;
  pendingPermission: PendingPermission | null;
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
