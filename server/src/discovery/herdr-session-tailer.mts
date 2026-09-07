import fs from "node:fs";
import type { WebSocket } from "ws";
import { convertJsonlRecordToAcpUpdates } from "./herdr-acp-converter.mjs";
import { HerdrAdapter } from "./herdr-adapter.mjs";

export interface TailerEventCallback {
  (message: Record<string, unknown>, senderWs?: WebSocket): void;
}

export class HerdrSessionTailer {
  readonly filePath: string;
  readonly sessionId: string;
  readonly paneId: string;

  private byteOffset = 0;
  private remainderBuffer = "";
  private watcher: fs.FSWatcher | null = null;
  private pollInterval: NodeJS.Timeout | null = null;
  private subscribers = new Set<WebSocket>();
  private isWorking = false;
  private lastInjectedPrompt: string | null = null;
  private lastInjectedWs: WebSocket | null = null;
  private isDestroyed = false;

  constructor(filePath: string, sessionId: string, paneId: string, initialOffset?: number) {
    this.filePath = filePath;
    this.sessionId = sessionId;
    this.paneId = paneId;

    if (typeof initialOffset === "number") {
      this.byteOffset = initialOffset;
    } else {
      try {
        if (fs.existsSync(filePath)) {
          this.byteOffset = fs.statSync(filePath).size;
        }
      } catch {
        this.byteOffset = 0;
      }
    }

    this.startWatching();
  }

  setLastInjectedPrompt(text: string, ws?: WebSocket): void {
    this.lastInjectedPrompt = text.trim();
    this.lastInjectedWs = ws ?? null;
    this.isWorking = true;
  }

  setByteOffset(offset: number): void {
    this.byteOffset = offset;
    this.remainderBuffer = "";
  }

  getByteOffset(): number {
    return this.byteOffset;
  }

  subscribe(ws: WebSocket): void {
    this.subscribers.add(ws);
  }

  unsubscribe(ws: WebSocket): void {
    this.subscribers.delete(ws);
    if (this.subscribers.size === 0) {
      this.destroy();
    }
  }

  hasSubscribers(): boolean {
    return this.subscribers.size > 0;
  }

  private startWatching(): void {
    try {
      if (fs.existsSync(this.filePath)) {
        this.watcher = fs.watch(this.filePath, () => {
          this.readNewBytes();
        });
        this.watcher.on("error", () => {
          // Fall back to polling if inotify fails
        });
      }
    } catch {
      // ignore watch errors
    }

    // 500ms safety polling for size changes and Herdr status sync
    this.pollInterval = setInterval(() => {
      this.readNewBytes();
      this.checkAgentStatus();
    }, 500);
  }

  private readNewBytes(): void {
    if (this.isDestroyed || !fs.existsSync(this.filePath)) return;

    try {
      const stat = fs.statSync(this.filePath);
      if (stat.size <= this.byteOffset) return;

      const bytesToRead = stat.size - this.byteOffset;
      const fd = fs.openSync(this.filePath, "r");
      const buffer = Buffer.alloc(bytesToRead);
      fs.readSync(fd, buffer, 0, bytesToRead, this.byteOffset);
      fs.closeSync(fd);
      this.byteOffset = stat.size;

      const chunk = this.remainderBuffer + buffer.toString("utf8");
      const lines = chunk.split("\n");

      // The last element is either "" or an incomplete JSON line
      this.remainderBuffer = lines.pop() ?? "";

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;

        let record: Record<string, any>;
        try {
          record = JSON.parse(trimmed);
        } catch {
          // Skip invalid JSON
          continue;
        }

        // Deduplicate user prompt echoed back from the file if mobile injected it
        if (record.type === "message" && record.message?.role === "user") {
          const userText = String(record.message.content?.[0]?.text || record.message.content || "").trim();
          if (this.lastInjectedPrompt && userText === this.lastInjectedPrompt) {
            this.lastInjectedPrompt = null;
            // Broadcast to other subscribers, but skip the injector
            const updates = convertJsonlRecordToAcpUpdates(record);
            for (const update of updates) {
              this.broadcast(
                {
                  type: "agent_event",
                  sessionId: this.sessionId,
                  event: update,
                },
                this.lastInjectedWs ?? undefined,
              );
            }
            this.lastInjectedWs = null;
            this.isWorking = true;
            continue;
          }
        }

        const updates = convertJsonlRecordToAcpUpdates(record);
        if (updates.length > 0) {
          this.isWorking = true;
          for (const update of updates) {
            this.broadcast({
              type: "agent_event",
              sessionId: this.sessionId,
              event: update,
            });
          }
        }
      }
    } catch (err) {
      // File may be locked or mid-rename, ignore transient read errors
    }
  }

  private async checkAgentStatus(): Promise<void> {
    if (this.isDestroyed || !this.isWorking) return;

    try {
      const agents = await HerdrAdapter.listAgents();
      const targetPane = this.paneId.replace(/^herdr:/, "");
      const current = agents.find((a) => a.pane_id === targetPane);

      if (current) {
        if (current.agent_status === "idle" || current.agent_status === "done") {
          // Agent finished turn
          this.isWorking = false;
          this.broadcast({
            type: "turn_ended",
            sessionId: this.sessionId,
          });
        } else if (current.agent_status === "working") {
          this.isWorking = true;
        }
      }
    } catch {
      // Ignore status check errors
    }
  }

  private broadcast(message: Record<string, unknown>, skipWs?: WebSocket): void {
    const payload = JSON.stringify(message);
    for (const ws of this.subscribers) {
      if (skipWs && ws === skipWs) continue;
      if (ws.readyState === 1 /* OPEN */) {
        try {
          ws.send(payload);
        } catch {
          // ignore closed socket error
        }
      }
    }
  }

  destroy(): void {
    if (this.isDestroyed) return;
    this.isDestroyed = true;

    if (this.watcher) {
      try {
        this.watcher.close();
      } catch {}
      this.watcher = null;
    }

    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }

    this.subscribers.clear();
    HerdrTailerRegistry.remove(this.sessionId);
  }
}

// ── Global Tailer Registry ─────────────────────────────────────────────

export class HerdrTailerRegistry {
  private static tailers = new Map<string, HerdrSessionTailer>();

  static getOrCreate(
    filePath: string,
    sessionId: string,
    paneId: string,
    initialOffset?: number,
  ): HerdrSessionTailer {
    let tailer = this.tailers.get(sessionId);
    if (!tailer) {
      tailer = new HerdrSessionTailer(filePath, sessionId, paneId, initialOffset);
      this.tailers.set(sessionId, tailer);
    }
    return tailer;
  }

  static get(sessionId: string): HerdrSessionTailer | undefined {
    return this.tailers.get(sessionId);
  }

  static remove(sessionId: string): void {
    this.tailers.delete(sessionId);
  }

  static cleanupAll(): void {
    for (const tailer of this.tailers.values()) {
      tailer.destroy();
    }
    this.tailers.clear();
  }
}
