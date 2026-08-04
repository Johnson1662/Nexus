import 'package:flutter/material.dart';

/// Helper utility for Agent visual recognition, icons, and formatting.
class AgentUtils {
  AgentUtils._();

  /// Returns a distinctive IconData for a given agent name/ID.
  static IconData getIcon(String? agentName) {
    if (agentName == null || agentName.trim().isEmpty) {
      return Icons.smart_toy_outlined;
    }
    final name = agentName.toLowerCase();
    if (name.contains('opencode')) {
      return Icons.code_rounded;
    } else if (name.contains('codex')) {
      return Icons.auto_awesome_rounded;
    } else if (name.contains('claude')) {
      return Icons.smart_toy_outlined;
    } else if (name.contains('omp')) {
      return Icons.memory_rounded;
    } else if (name.contains('deepseek')) {
      return Icons.psychology_outlined;
    } else if (name.contains('gemini')) {
      return Icons.auto_awesome_mosaic_rounded;
    } else if (name.contains('terminal') || name.contains('shell') || name.contains('bash')) {
      return Icons.terminal_rounded;
    }
    return Icons.smart_toy_outlined;
  }

  /// Returns a clean display label for an agent string.
  static String getDisplayName(String? agentName) {
    if (agentName == null || agentName.trim().isEmpty) return 'Agent';
    final name = agentName.trim();
    final lower = name.toLowerCase();
    if (lower == 'opencode') return 'OpenCode';
    if (lower == 'codex-acp' || lower == 'codex') return 'Codex';
    if (lower == 'claude' || lower == 'claude-code') return 'Claude Code';
    if (lower == 'omp') return 'OMP';
    return name;
  }
}
