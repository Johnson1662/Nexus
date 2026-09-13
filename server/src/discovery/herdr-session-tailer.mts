import fs from "node:fs";
import type { WebSocket } from "ws";
import { convertJsonlRecordToAcpUpdates } from "./herdr-acp-converter.mjs";
import { HerdrAdapter } from "./herdr-adapter.mjs";
import { getAmbientSession } from "./ambient-session.mjs";

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
  /**
   * Sockets whose live events are queued while a history snapshot is in flight.
   * The snapshot replaces the client's rendered history, so any event delivered
   * before the snapshot is taken is already inside it; an event that arrives
   * during the read must be replayed after the snapshot or it is lost.
   */
  private holding = new Map<WebSocket, Record<string, unknown>[]>();
  private isWorking = false;
  private lastInjectedPrompt: string | null = null;
  private lastInjectedWs: WebSocket | null = null;
  private isDestroyed = false;
  private trackHerdrStatus = true;
  private lastAgentStatus = "unknown";
  private checkingStatus = false;
  private awaitingAgentStart = false;
  private promptAcceptedAt = 0;

  constructor(
    filePath: string,
    sessionId: string,
    paneId: string,
    initialOffset?: number,
    trackHerdrStatus = true,
  ) {
    this.filePath = filePath;
    this.sessionId = sessionId;
    this.paneId = paneId;
    this.trackHerdrStatus = trackHerdrStatus;

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
    this.awaitingAgentStart = true;
    this.promptAcceptedAt = Date.now();
  }

  markWorking(): void {
    this.isWorking = true;
  }

  getLastInjectedPrompt(): string | null {
    return this.lastInjectedPrompt;
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

  /** Queue this socket's live events until release() (used around a snapshot). */
  hold(ws: WebSocket): void {
    if (!this.holding.has(ws)) this.holding.set(ws, []);
  }

  /** Deliver everything queued while held, then resume direct delivery. */
  release(ws: WebSocket): void {
    const queued = this.holding.get(ws);
    this.holding.delete(ws);
    if (!queued?.length) return;
    if (ws.readyState !== 1 /* OPEN */) return;
    for (const message of queued) {
      try {
        ws.send(JSON.stringify(message));
      } catch {
        // ignore closed socket error
      }
    }
  }

  unsubscribe(ws: WebSocket): void {
    this.holding.delete(ws);
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
          this.awaitingAgentStart = false;
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
    if (this.isDestroyed || !this.trackHerdrStatus || this.checkingStatus) return;
    this.checkingStatus = true;

    try {
      const currentStatus = this.sessionId.startsWith("ambient:")
        ? getAmbientSession(this.sessionId)?.status
        : (await HerdrAdapter.listAgents())
          .find((a) => a.pane_id === this.paneId.replace(/^herdr:/, ""))
          ?.agent_status;
      if (currentStatus) {
        if (currentStatus !== this.lastAgentStatus) {
          this.lastAgentStatus = currentStatus;
          this.broadcast({
            type: "session_status",
            sessionId: this.sessionId,
            status: currentStatus,
          });
        }
        if (currentStatus === "idle" || currentStatus === "done") {
          if (this.awaitingAgentStart && Date.now() - this.promptAcceptedAt < 3000) return;
          if (this.isWorking) {
          // Agent finished turn
            this.isWorking = false;
            this.broadcast({ type: "turn_ended", sessionId: this.sessionId });
          }
        } else if (currentStatus === "working" || currentStatus === "running") {
          this.isWorking = true;
          this.awaitingAgentStart = false;
        } else if (currentStatus === "blocked" || currentStatus === "waiting_input") {
          this.awaitingAgentStart = false;
        }
      }
    } catch {
      // Ignore status check errors
    } finally {
      this.checkingStatus = false;
    }
  }

  private broadcast(message: Record<string, unknown>, skipWs?: WebSocket): void {
    for (const ws of this.subscribers) {
      if (skipWs && ws === skipWs) continue;
      const queue = this.holding.get(ws);
      if (queue) {
        queue.push(message);
        continue;
      }
      if (ws.readyState === 1 /* OPEN */) {
        try {
          ws.send(JSON.stringify(message));
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
  private static pendingInjectedPrompts = new Map<string, { text: string; ws?: WebSocket; timestamp: number }>();

  static recordPendingPrompt(sessionId: string, text: string, ws?: WebSocket): void {
    this.pendingInjectedPrompts.set(sessionId, { text: text.trim(), ws, timestamp: Date.now() });
  }

  static consumePendingPrompt(sessionId: string): { text: string; ws?: WebSocket } | null {
    const pending = this.pendingInjectedPrompts.get(sessionId);
    if (!pending) return null;
    if (Date.now() - pending.timestamp > 30_000) {
      this.pendingInjectedPrompts.delete(sessionId);
      return null;
    }
    this.pendingInjectedPrompts.delete(sessionId);
    return pending;
  }

  static deletePendingPrompt(sessionId: string): void {
    this.pendingInjectedPrompts.delete(sessionId);
  }

  static getOrCreate(
    filePath: string,
    sessionId: string,
    paneId: string,
    initialOffset?: number,
    trackHerdrStatus = true,
  ): HerdrSessionTailer {
    let tailer = this.tailers.get(sessionId);
    if (!tailer) {
      tailer = new HerdrSessionTailer(filePath, sessionId, paneId, initialOffset, trackHerdrStatus);
      const pending = this.consumePendingPrompt(sessionId);
      if (pending) {
        tailer.setLastInjectedPrompt(pending.text, pending.ws);
      }
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
    this.pendingInjectedPrompts.clear();
  }
}
