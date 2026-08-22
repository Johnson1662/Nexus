import { Buffer } from "node:buffer";

export const MAX_AGENT_EVENT_BYTES = 512 * 1024;
export const MAX_REPLAY_BYTES_PER_SESSION = 2 * 1024 * 1024;
export const MAX_TOOL_CONTENT_BYTES = 512 * 1024;
export const MAX_FILE_EVENT_BYTES = 512 * 1024;

export interface Utf8Truncation {
  text: string;
  originalBytes: number;
  retainedBytes: number;
  truncated: boolean;
}

/** Truncate by UTF-8 bytes without splitting a Unicode code point. */
export function truncateUtf8(value: string, maxBytes: number): Utf8Truncation {
  const originalBytes = Buffer.byteLength(value, "utf8");
  if (originalBytes <= maxBytes) {
    return { text: value, originalBytes, retainedBytes: originalBytes, truncated: false };
  }

  let retainedBytes = 0;
  const accepted: string[] = [];
  for (const codePoint of value) {
    const codePointBytes = Buffer.byteLength(codePoint, "utf8");
    if (retainedBytes + codePointBytes > maxBytes) break;
    accepted.push(codePoint);
    retainedBytes += codePointBytes;
  }
  return { text: accepted.join(""), originalBytes, retainedBytes, truncated: true };
}

type JsonRecord = Record<string, unknown>;

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

interface BoundedValue {
  value: unknown;
  truncated: boolean;
  originalBytes: number;
  retainedBytes: number;
}

/**
 * Recursively bounds strings while preserving the surrounding JSON shape.
 * The caller still has to enforce the serialized envelope budget because a
 * payload may contain many individually-small fields.
 */
function boundValue(value: unknown, maxStringBytes: number): BoundedValue {
  if (typeof value === "string") {
    const result = truncateUtf8(value, maxStringBytes);
    return {
      value: result.text,
      truncated: result.truncated,
      originalBytes: result.originalBytes,
      retainedBytes: result.retainedBytes,
    };
  }
  if (Array.isArray(value)) {
    let truncated = false;
    let originalBytes = 0;
    let retainedBytes = 0;
    const bounded = value.map((entry) => {
      const result = boundValue(entry, maxStringBytes);
      truncated ||= result.truncated;
      originalBytes += result.originalBytes;
      retainedBytes += result.retainedBytes;
      return result.value;
    });
    return { value: bounded, truncated, originalBytes, retainedBytes };
  }
  if (!isRecord(value)) {
    return { value, truncated: false, originalBytes: 0, retainedBytes: 0 };
  }

  const bounded: JsonRecord = {};
  let truncated = false;
  let originalBytes = 0;
  let retainedBytes = 0;
  for (const [key, child] of Object.entries(value)) {
    const result = boundValue(child, maxStringBytes);
    bounded[key] = result.value;
    truncated ||= result.truncated;
    originalBytes += result.originalBytes;
    retainedBytes += result.retainedBytes;
  }
  if (truncated) {
    bounded.truncated = true;
    bounded.originalBytes = originalBytes;
    bounded.retainedBytes = retainedBytes;
  }
  return { value: bounded, truncated, originalBytes, retainedBytes };
}

function serialize(value: JsonRecord): { payload: string; payloadBytes: number } {
  const payload = JSON.stringify(value) ?? "{}";
  return { payload, payloadBytes: Buffer.byteLength(payload, "utf8") };
}

export interface BoundedPayload {
  value: JsonRecord;
  payload: string;
  payloadBytes: number;
  truncated: boolean;
}

function minimalEvent(event: unknown): JsonRecord {
  if (!isRecord(event)) {
    return { sessionUpdate: "content", truncated: true };
  }

  const compact: JsonRecord = {};
  for (const key of [
    "sessionUpdate",
    "toolCallId",
    "status",
    "path",
    "terminalId",
    "terminalStatus",
  ]) {
    const value = event[key];
    if (typeof value === "string") compact[key] = value;
  }
  if (Array.isArray(event.toolCallContent)) {
    compact.toolCallContent = event.toolCallContent.map((block) => {
      if (!isRecord(block)) return { type: "content", content: { type: "text", text: "" } };
      const boundedBlock: JsonRecord = {};
      if (typeof block.type === "string") boundedBlock.type = block.type;
      if (isRecord(block.content)) {
        const content: JsonRecord = {};
        for (const key of ["type", "path", "terminalId", "oldText", "newText", "text"]) {
          if (typeof block.content[key] === "string") content[key] = block.content[key];
        }
        boundedBlock.content = content;
      } else {
        boundedBlock.content = { type: "text", text: "" };
      }
      return boundedBlock;
    });
  }
  compact.truncated = true;
  return compact;
}

function minimalPayload(payload: JsonRecord): JsonRecord {
  const compact: JsonRecord = {};
  for (const key of ["type", "sessionId", "messageId"]) {
    if (typeof payload[key] === "string") compact[key] = payload[key];
  }
  compact.event = minimalEvent(payload.event);
  return compact;
}

function boundWithShape(
  payload: JsonRecord,
  maxPayloadBytes: number,
  maxStringBytes: number,
  fallback: () => JsonRecord,
): BoundedPayload {
  const initial = boundValue(payload, maxStringBytes);
  const initialValue = initial.value as JsonRecord;
  const initialSerialized = serialize(initialValue);
  if (initialSerialized.payloadBytes <= maxPayloadBytes) {
    return {
      value: initialValue,
      payload: initialSerialized.payload,
      payloadBytes: initialSerialized.payloadBytes,
      truncated: initial.truncated,
    };
  }

  // Find the largest per-string limit that fits the whole JSON envelope. This
  // keeps structured ACP blocks intact while making room for their metadata.
  let low = 0;
  let high = maxStringBytes;
  let best: BoundedPayload | undefined;
  for (let attempt = 0; attempt < 22 && low <= high; attempt += 1) {
    const limit = Math.floor((low + high) / 2);
    const candidate = boundValue(payload, limit);
    const candidateValue = candidate.value as JsonRecord;
    const candidateSerialized = serialize(candidateValue);
    if (candidateSerialized.payloadBytes <= maxPayloadBytes) {
      best = {
        value: candidateValue,
        payload: candidateSerialized.payload,
        payloadBytes: candidateSerialized.payloadBytes,
        truncated: true,
      };
      low = limit + 1;
    } else {
      high = limit - 1;
    }
  }
  if (best) return best;

  // A payload can still be too large at a zero string limit when it contains
  // an unexpectedly large array/object graph. Preserve the event object and
  // its identity fields instead of converting it to an opaque JSON string.
  const compact = fallback();
  const compactSerialized = serialize(compact);
  return {
    value: compact,
    payload: compactSerialized.payload,
    payloadBytes: compactSerialized.payloadBytes,
    truncated: true,
  };
}

/**
 * Bound JSON payloads without replacing a structured event with a string.
 * Agent/file callers use the more specific functions below.
 */
export function boundJsonPayload(
  payload: JsonRecord,
  maxPayloadBytes: number,
  maxStringBytes: number,
): BoundedPayload {
  return boundWithShape(payload, maxPayloadBytes, maxStringBytes, () => minimalPayload(payload));
}

const TOOL_TEXT_KEYS = new Set(["content", "text", "oldText", "newText"]);

interface ToolContentLimit {
  value: unknown;
  truncated: boolean;
  originalBytes: number;
  retainedBytes: number;
}

/** Limit only text-bearing fields inside a tool-call event. */
function limitToolContentFields(value: unknown, maxBytes: number, active = false): ToolContentLimit {
  if (typeof value === "string") {
    return { value, truncated: false, originalBytes: 0, retainedBytes: 0 };
  }
  if (Array.isArray(value)) {
    let remaining = maxBytes;
    let truncated = false;
    let originalBytes = 0;
    let retainedBytes = 0;
    const bounded = value.map((entry) => {
      const result = limitToolContentFields(entry, remaining, active);
      remaining -= result.retainedBytes;
      truncated ||= result.truncated;
      originalBytes += result.originalBytes;
      retainedBytes += result.retainedBytes;
      return result.value;
    });
    return { value: bounded, truncated, originalBytes, retainedBytes };
  }
  if (!isRecord(value)) return { value, truncated: false, originalBytes: 0, retainedBytes: 0 };
  // Terminal output has its own 256KB per-terminal limit. Do not consume the
  // cumulative ACP tool-card budget with repeated deltas from that terminal.
  if (value.type === "terminal") {
    return { value, truncated: false, originalBytes: 0, retainedBytes: 0 };
  }

  const bounded: JsonRecord = {};
  let remaining = maxBytes;
  let truncated = false;
  let originalBytes = 0;
  let retainedBytes = 0;
  for (const [key, child] of Object.entries(value)) {
    if (active && TOOL_TEXT_KEYS.has(key) && typeof child === "string") {
      const result = truncateUtf8(child, remaining);
      bounded[key] = result.text;
      remaining -= result.retainedBytes;
      truncated ||= result.truncated;
      originalBytes += result.originalBytes;
      retainedBytes += result.retainedBytes;
      continue;
    }
    const result = limitToolContentFields(child, remaining, active || key === "toolCallContent");
    bounded[key] = result.value;
    remaining -= result.retainedBytes;
    truncated ||= result.truncated;
    originalBytes += result.originalBytes;
    retainedBytes += result.retainedBytes;
  }
  return { value: bounded, truncated, originalBytes, retainedBytes };
}

function toolContentBytes(value: unknown, active = false): number {
  if (typeof value === "string") return 0;
  if (Array.isArray(value)) return value.reduce((sum, child) => sum + toolContentBytes(child, active), 0);
  if (!isRecord(value)) return 0;
  if (value.type === "terminal") return 0;

  let total = 0;
  for (const [key, child] of Object.entries(value)) {
    if (active && TOOL_TEXT_KEYS.has(key) && typeof child === "string") {
      total += Buffer.byteLength(child, "utf8");
    } else {
      total += toolContentBytes(child, active || key === "toolCallContent");
    }
  }
  return total;
}

export interface AgentEventBudgetOptions {
  /** Remaining cumulative text budget for this tool call, if applicable. */
  toolContentByteLimit?: number;
}

export function countToolContentBytes(payload: JsonRecord): number {
  const event = payload.event;
  if (!isRecord(event) || event.sessionUpdate !== "tool_call_update") return 0;
  return toolContentBytes(event, true);
}

export function boundAgentEventPayload(
  payload: JsonRecord,
  options: AgentEventBudgetOptions = {},
): BoundedPayload {
  let prepared = payload;
  const event = payload.event;
  if (options.toolContentByteLimit !== undefined && isRecord(event) && event.sessionUpdate === "tool_call_update") {
    const limited = limitToolContentFields(event, Math.max(0, options.toolContentByteLimit), true);
    prepared = {
      ...payload,
      event: {
        ...limited.value as JsonRecord,
        ...(limited.truncated
          ? { truncated: true, originalBytes: limited.originalBytes, retainedBytes: limited.retainedBytes }
          : {}),
      },
    };
  }
  return boundWithShape(
    prepared,
    MAX_AGENT_EVENT_BYTES,
    MAX_TOOL_CONTENT_BYTES,
    () => minimalPayload(prepared),
  );
}

function boundFilePayload(payload: JsonRecord, key: "content" | "diff"): BoundedPayload {
  const originalText = typeof payload[key] === "string" ? payload[key] as string : "";
  const basePayload = { ...payload };
  delete basePayload[key];
  const boundedBase = boundValue(basePayload, 64 * 1024);
  const base = boundedBase.value as JsonRecord;

  const build = (maxTextBytes: number): BoundedPayload => {
    const text = truncateUtf8(originalText, maxTextBytes);
    const value: JsonRecord = {
      ...base,
      [key]: text.text,
      ...(text.truncated || boundedBase.truncated
        ? {
            truncated: true,
            originalBytes: text.originalBytes,
            retainedBytes: text.retainedBytes,
          }
        : {}),
    };
    const serialized = serialize(value);
    return {
      value,
      payload: serialized.payload,
      payloadBytes: serialized.payloadBytes,
      truncated: text.truncated || boundedBase.truncated,
    };
  };

  const initial = build(MAX_FILE_EVENT_BYTES);
  if (initial.payloadBytes <= MAX_FILE_EVENT_BYTES) return initial;

  let low = 0;
  let high = MAX_FILE_EVENT_BYTES;
  let best: BoundedPayload | undefined;
  for (let attempt = 0; attempt < 22 && low <= high; attempt += 1) {
    const limit = Math.floor((low + high) / 2);
    const candidate = build(limit);
    if (candidate.payloadBytes <= MAX_FILE_EVENT_BYTES) {
      best = { ...candidate, truncated: true };
      low = limit + 1;
    } else {
      high = limit - 1;
    }
  }
  if (best) return best;

  // The normal path always fits because only file text is large. Keep the
  // required top-level fields even for an adversarially-large path/metadata.
  const compact: JsonRecord = {
    type: payload.type,
    path: typeof payload.path === "string" ? truncateUtf8(payload.path, 1024).text : "",
    [key]: "",
    truncated: true,
    originalBytes: Buffer.byteLength(originalText, "utf8"),
    retainedBytes: 0,
  };
  const serialized = serialize(compact);
  return { value: compact, payload: serialized.payload, payloadBytes: serialized.payloadBytes, truncated: true };
}

export function boundFileEventPayload(payload: JsonRecord): BoundedPayload {
  const key = payload.type === "file_diff" ? "diff" : "content";
  return boundFilePayload(payload, key);
}
