import { readFileSync, createReadStream } from "node:fs";
import readline from "node:readline";

export interface AcpEventPayload {
  sessionUpdate: string;
  [key: string]: unknown;
}

/**
 * Extracts plain text from various content payload formats:
 * - Direct string: "hello"
 * - Array of blocks: [{ type: "text", text: "..." }]
 * - Single block: { type: "text", text: "..." }
 */
export function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!content) return "";

  if (Array.isArray(content)) {
    return content
      .map((item) => {
        if (typeof item === "string") return item;
        if (item && typeof item === "object") {
          const m = item as Record<string, unknown>;
          if (typeof m.text === "string") return m.text;
          if (m.content) return extractText(m.content);
        }
        return "";
      })
      .join("");
  }

  if (typeof content === "object") {
    const m = content as Record<string, unknown>;
    if (typeof m.text === "string") return m.text;
    if (m.content) return extractText(m.content);
  }

  return "";
}

/**
 * Converts a parsed JSON record from an agent's session.jsonl into zero or more ACP events.
 */
export function convertJsonlRecordToAcpUpdates(record: Record<string, any>): AcpEventPayload[] {
  if (!record || typeof record !== "object") return [];

  const type = record.type;
  const updates: AcpEventPayload[] = [];

  // 1. User message
  if (type === "message" && record.message?.role === "user") {
    const text = extractText(record.message.content);
    if (text) {
      updates.push({
        sessionUpdate: "user_message_chunk",
        content: { type: "text", text },
      });
    }
    return updates;
  }

  // 2. Assistant message (thinking, tool calls, text response)
  if (type === "message" && record.message?.role === "assistant") {
    const content = record.message.content;
    if (Array.isArray(content)) {
      for (const part of content) {
        if (!part || typeof part !== "object") continue;

        // Thinking chunk
        if (part.type === "thinking" && part.thinking) {
          const trimmedThinking = String(part.thinking).trim();
          if (trimmedThinking) {
            updates.push({
              sessionUpdate: "agent_thought_chunk",
              content: { type: "text", text: trimmedThinking },
            });
          }
          continue;
        }

        // Assistant response text chunk
        if (part.type === "text" && part.text) {
          updates.push({
            sessionUpdate: "agent_message_chunk",
            content: { type: "text", text: String(part.text) },
          });
        }

        // Tool call declaration
        if (part.type === "toolCall" && part.id) {
          updates.push({
            sessionUpdate: "tool_call",
            toolCallId: String(part.id),
            title: String(part.name || "tool"),
            rawInput: part.arguments ?? (part.intent ? { intent: part.intent } : {}),
          });
        }
      }
    } else if (typeof content === "string" && content) {
      updates.push({
        sessionUpdate: "agent_message_chunk",
        content: { type: "text", text: content },
      });
    }
    return updates;
  }

  // 3. Explicit tool execution start event (timestamp/intent marker)
  // (tool_call is already declared with arguments & intent in the assistant message;
  // custom:tool_execution_start is an internal timestamp marker and must not emit duplicate tool_call events)

  // 4. Tool execution result (status and output)
  if (type === "message" && (record.message?.role === "toolResult" || record.message?.role === "bashExecution")) {
    const m = record.message;
    const toolCallId = m.toolCallId || m.id;
    if (toolCallId) {
      const outputText = extractText(m.content);
      const isError = Boolean(m.isError);
      updates.push({
        sessionUpdate: "tool_call_update",
        toolCallId: String(toolCallId),
        status: isError ? "failed" : "completed",
        content: [
          {
            type: "content",
            content: {
              type: "text",
              text: outputText,
            },
          },
        ],
      });
    }
    return updates;
  }

  return updates;
}

/**
 * Converts multiple raw JSONL strings into ACP events.
 */
export function convertJsonlLinesToAcpUpdates(lines: string[]): AcpEventPayload[] {
  const allUpdates: AcpEventPayload[] = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const record = JSON.parse(trimmed);
      const updates = convertJsonlRecordToAcpUpdates(record);
      for (const u of updates) {
        allUpdates.push(u);
      }
    } catch {
      // Incomplete line or invalid JSON, skip
    }
  }
  return allUpdates;
}

/**
 * Reads the session.jsonl file and converts its recent history into a list of ACP events.
 * Defaults to the last 80 lines to ensure instant, zero-lag session loading without
 * replaying thousands of historical events from weeks ago.
 */
export async function readSessionJsonlToAcpUpdates(
  filePath: string,
  maxRecentLines = 80,
): Promise<AcpEventPayload[]> {
  const content = readFileSync(filePath, "utf8");
  const rawLines = content.split("\n");
  const lines = rawLines.filter((l) => l.trim().length > 0);
  const sliced = maxRecentLines > 0 && lines.length > maxRecentLines ? lines.slice(-maxRecentLines) : lines;
  return convertJsonlLinesToAcpUpdates(sliced);
}

/**
 * Extracts ONLY the latest conversation turn (from the last user prompt to EOF).
 * Enables sub-10ms initial session open with zero lag.
 */
export async function readSessionJsonlRecentTurn(filePath: string): Promise<AcpEventPayload[]> {
  const content = readFileSync(filePath, "utf8");
  const rawLines = content.split("\n");
  const lines = rawLines.filter((l) => l.trim().length > 0);

  let lastUserIdx = -1;
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const o = JSON.parse(lines[i]);
      if (o.type === "message" && o.message?.role === "user") {
        lastUserIdx = i;
        break;
      }
    } catch {}
  }

  const turnLines = lastUserIdx >= 0 && (lines.length - lastUserIdx) <= 150
    ? lines.slice(lastUserIdx)
    : lines.slice(-50);
  return convertJsonlLinesToAcpUpdates(turnLines);
}

/**
 * Extracts the complete history from the beginning of time.
 * Used for background asynchronous full hydration without UI blocking.
 */
export async function readSessionJsonlFullHistory(filePath: string): Promise<AcpEventPayload[]> {
  const content = readFileSync(filePath, "utf8");
  const rawLines = content.split("\n");
  const lines = rawLines.filter((l) => l.trim().length > 0);
  return convertJsonlLinesToAcpUpdates(lines);
}
