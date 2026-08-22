export type JsonRecord = Record<string, unknown>;

export type ClientMessageParseResult =
  | { ok: true; message: JsonRecord }
  | { ok: false; code: "INVALID_JSON" | "INVALID_MESSAGE"; text: string };

const STRING_FIELDS = [
  "sessionId",
  "text",
  "agent",
  "prompt",
  "cwd",
  "model",
  "modeId",
  "requestId",
  "outcome",
  "optionId",
  "agentId",
  "command",
  "name",
  "configId",
  "path",
  "hostId",
  "lastMessageId",
];

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasValidOptionalFields(message: JsonRecord): boolean {
  for (const field of STRING_FIELDS) {
    if (field in message && typeof message[field] !== "string") return false;
  }
  if ("refresh" in message && typeof message.refresh !== "boolean") return false;
  if (
    "args" in message &&
    (!Array.isArray(message.args) || message.args.some((arg) => typeof arg !== "string"))
  ) {
    return false;
  }
  return true;
}

/** Validate the small, intentionally permissive envelope shared by all WS messages. */
export function isValidClientMessage(value: unknown): value is JsonRecord {
  if (!isRecord(value) || typeof value.type !== "string" || value.type.trim().length === 0) {
    return false;
  }
  if (!hasValidOptionalFields(value)) return false;

  // Layered messages carry the session message in a required object. This also
  // prevents `message: null` from reaching the router and throwing. Only one
  // layer is part of the protocol; rejecting another `session` layer keeps
  // validation iterative and immune to attacker-controlled recursion depth.
  if (value.type === "session") {
    return isRecord(value.message) &&
      value.message.type !== "session" &&
      typeof value.message.type === "string" &&
      value.message.type.trim().length > 0 &&
      hasValidOptionalFields(value.message);
  }
  return true;
}

export function parseClientMessage(raw: string): ClientMessageParseResult {
  let decoded: unknown;
  try {
    decoded = JSON.parse(raw);
  } catch {
    return { ok: false, code: "INVALID_JSON", text: "Invalid JSON message" };
  }
  try {
    if (!isValidClientMessage(decoded)) {
      return { ok: false, code: "INVALID_MESSAGE", text: "Message does not match the WS protocol" };
    }
    return { ok: true, message: decoded };
  } catch {
    // Validation exceptions are handled as invalid messages rather than
    // escaping the WS message callback.
    return { ok: false, code: "INVALID_MESSAGE", text: "Message does not match the WS protocol" };
  }
}
