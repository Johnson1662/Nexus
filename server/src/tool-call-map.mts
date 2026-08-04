import path from "node:path";
import type { SessionState } from "./acp/types.mjs";
import { sessionManager } from "./session-manager.mjs";

function resolveToolPath(cwd: string, toolPath: string): string {
  return path.isAbsolute(toolPath)
    ? path.normalize(toolPath)
    : path.resolve(cwd || process.cwd(), toolPath);
}

export function recordToolCallIds(sess: SessionState, update: unknown): void {
  const toolCallEvt = update as any;
  if (toolCallEvt?.sessionUpdate !== "tool_call" || !toolCallEvt?.toolCallId) return;

  const rawId = String(toolCallEvt.toolCallId);
  const cwd = sess.cwd || process.cwd();
  const locations = (toolCallEvt.locations || []) as Array<{ path?: string }>;
  const rawInput = toolCallEvt.rawInput as Record<string, unknown> | undefined;

  for (const loc of locations) {
    if (!loc.path) continue;
    const resolvedPath = resolveToolPath(cwd, loc.path);
    sess.toolCallIdMap.set(`read:${resolvedPath}`, rawId);
    sess.toolCallIdMap.set(`write:${resolvedPath}`, rawId);
  }

  if (locations.length === 0 && rawInput && typeof rawInput.path === "string") {
    const resolvedPath = resolveToolPath(cwd, rawInput.path);
    if (toolCallEvt.kind === "read") {
      sess.toolCallIdMap.set(`read:${resolvedPath}`, rawId);
    } else if (toolCallEvt.kind === "edit") {
      sess.toolCallIdMap.set(`write:${resolvedPath}`, rawId);
    } else {
      sess.toolCallIdMap.set(`read:${resolvedPath}`, rawId);
      sess.toolCallIdMap.set(`write:${resolvedPath}`, rawId);
    }
  }

  sess.lastToolCallId = rawId;
  sessionManager.trimToolCallIds(sess);
}
