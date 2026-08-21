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

interface BoundedValue {
  value: unknown;
  truncated: boolean;
  originalBytes: number;
  retainedBytes: number;
}

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
  if (typeof value !== "object" || value === null) {
    return { value, truncated: false, originalBytes: 0, retainedBytes: 0 };
  }

  const bounded: Record<string, unknown> = {};
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

export interface BoundedPayload {
  value: Record<string, unknown>;
  payload: string;
  payloadBytes: number;
  truncated: boolean;
}

/**
 * Bound JSON payloads while retaining their shape for normal client renders.
 * If many fields together still exceed the envelope budget, fall back to a
 * compact, explicitly marked representation instead of keeping an oversized
 * replay entry alive.
 */
export function boundJsonPayload(
  payload: Record<string, unknown>,
  maxPayloadBytes: number,
  maxStringBytes: number,
): BoundedPayload {
  const originalPayload = JSON.stringify(payload) ?? "";
  const originalPayloadBytes = Buffer.byteLength(originalPayload, "utf8");
  const originalEvent = payload.event;
  const originalEventText = JSON.stringify(originalEvent) ?? String(originalEvent ?? "");
  const bounded = boundValue(payload, maxStringBytes);
  let value = bounded.value as Record<string, unknown>;
  let serialized = JSON.stringify(value);
  let payloadBytes = Buffer.byteLength(serialized, "utf8");
  if (payloadBytes <= maxPayloadBytes) {
    return { value, payload: serialized, payloadBytes, truncated: bounded.truncated };
  }

  const originalBytes = originalPayloadBytes;
  const eventType =
    typeof value.event === "object" && value.event !== null && !Array.isArray(value.event) &&
    typeof (value.event as Record<string, unknown>).sessionUpdate === "string"
      ? (value.event as Record<string, unknown>).sessionUpdate
      : "content";
  let contentLimit = maxPayloadBytes;
  let compact: Record<string, unknown>;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const content = truncateUtf8(originalEventText, Math.max(0, contentLimit));
    compact = {
      type: value.type,
      sessionId: value.sessionId,
      messageId: value.messageId,
      event: {
        sessionUpdate: eventType,
        content: content.text,
        truncated: true,
        originalBytes,
        retainedBytes: content.retainedBytes,
      },
    };
    serialized = JSON.stringify(compact);
    payloadBytes = Buffer.byteLength(serialized, "utf8");
    if (payloadBytes <= maxPayloadBytes) {
      return { value: compact, payload: serialized, payloadBytes, truncated: true };
    }
    contentLimit = Math.max(0, contentLimit - (payloadBytes - maxPayloadBytes) - 1024);
  }

  // The envelope identifiers are bounded by the WS schema in normal use. The
  // final fallback remains valid JSON even if an unexpected identifier is huge.
  compact = {
    type: "error",
    code: "PAYLOAD_TRUNCATED",
    text: "Payload exceeded the event byte budget",
  };
  serialized = JSON.stringify(compact);
  payloadBytes = Buffer.byteLength(serialized, "utf8");
  return { value: compact, payload: serialized, payloadBytes, truncated: true };
}

export function boundAgentEventPayload(payload: Record<string, unknown>): BoundedPayload {
  return boundJsonPayload(payload, MAX_AGENT_EVENT_BYTES, MAX_TOOL_CONTENT_BYTES);
}

export function boundFileEventPayload(payload: Record<string, unknown>): BoundedPayload {
  return boundJsonPayload(payload, MAX_FILE_EVENT_BYTES, MAX_FILE_EVENT_BYTES);
}
