import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/theme.dart';
import '../models/ws_protocol.dart';

enum _RiskLevel { low, medium, high }

class _ParsedCommand {
  final String command;
  final String toolName;
  final Map<String, String> arguments;
  const _ParsedCommand({
    required this.command,
    required this.toolName,
    this.arguments = const {},
  });
}

class PermissionSheetWidget extends StatelessWidget {
  final PendingPermission permission;
  final void Function(String optionId) onSelect;

  const PermissionSheetWidget({
    super.key,
    required this.permission,
    required this.onSelect,
  });

  static final _highPatterns = RegExp(
    r'\b(rm(\s+-[rf]+)?\b|git\s+reset\s+--hard\b|\bdrop\b|\bformat\b|\bdd\b|\bmkfs\b|\bfdisk\b|\bshred\b|\bkill\s+-9\b|\b>:?\s|2>\s?/dev/null)',
    caseSensitive: false,
  );
  static final _mediumPatterns = RegExp(
    r'\b(sudo|write|edit|exec|bash|sh\b|zsh|sed\s+-i|mv\b|cp\b|chmod|chown|install|ln\s+-s|apt\s+(install|remove)|npm\s+(install|publish|uninstall)|pip\s+install|curl\s+-[^\s]*o|wget\b|git\s+push|git\s+merge|git\s+rebase|systemctl|service\b|docker\s+|kubectl\s+apply)',
    caseSensitive: false,
  );

  _RiskLevel _classifyRisk(String raw) {
    if (_highPatterns.hasMatch(raw)) return _RiskLevel.high;
    if (_mediumPatterns.hasMatch(raw)) return _RiskLevel.medium;
    // 未知命令默认高风险（fail-closed）
    return _RiskLevel.high;
  }

  /// Parse the raw toolCall Map.toString() into a structured _ParsedCommand.
  _ParsedCommand _parseCommand() {
    final raw = permission.toolCall.trim();
    if (raw.isEmpty || !raw.startsWith('{') || !raw.endsWith('}')) {
      return _ParsedCommand(command: raw.isEmpty ? '(empty)' : raw, toolName: '');
    }

    final inner = raw.substring(1, raw.length - 1);
    final pairs = <String, String>{};

    // Parse key: value pairs from Map.toString() format.
    // Handles quoted and unquoted values, skips nested braces.
    final kvRegex = RegExp(r"""(\w+):\s*(?:"([^"]*)"|'([^']*)'|([^,{}]+))""");
    for (final m in kvRegex.allMatches(inner)) {
      final key = m.group(1)!;
      final value = (m.group(2) ?? m.group(3) ?? m.group(4) ?? '').trim();
      if (value.isNotEmpty) {
        pairs[key] = value;
      }
    }

    // toolName: look up toolName or name key
    final toolName = pairs['toolName'] ?? pairs['name'] ?? '';

    // command: first meaningful value from preferred keys
    String command = '';
    for (final key in ['command', 'args', 'path', 'name']) {
      if (pairs.containsKey(key) && pairs[key]!.isNotEmpty) {
        command = pairs[key]!;
        break;
      }
    }
    if (command.isEmpty) {
      // fallback to first non-empty value
      command = pairs.values.firstWhere((v) => v.isNotEmpty, orElse: () => raw);
    }

    // arguments: everything except the keys used for toolName and command
    const usedKeys = {'toolName', 'name', 'command', 'args', 'path'};
    final arguments = <String, String>{
      for (final e in pairs.entries)
        if (!usedKeys.contains(e.key)) e.key: e.value
    };

    return _ParsedCommand(command: command, toolName: toolName, arguments: arguments);
  }

  Widget _buildRiskChip(String toolName, _RiskLevel level) {
    final (Color bg, Color fg, String label) = switch (level) {
      _RiskLevel.high => (
        AppColors.error.withAlpha(40),
        AppColors.error,
        '高风险',
      ),
      _RiskLevel.medium => (
        const Color(0xFFE08A00).withAlpha(40),
        const Color(0xFFE08A00),
        '中风险',
      ),
      _RiskLevel.low => (
        AppColors.success.withAlpha(40),
        AppColors.success,
        '低风险',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(BuildContext context) {
    // Partition options into allow-type and deny-type
    final allowOpts = <PermissionOption>[];
    final denyOpts = <PermissionOption>[];
    final otherOpts = <PermissionOption>[];

    for (final opt in permission.options) {
      final kind = opt.kind.toLowerCase();
      if (kind.startsWith('allow')) {
        allowOpts.add(opt);
      } else if (kind.startsWith('deny') || kind.startsWith('reject')) {
        denyOpts.add(opt);
      } else {
        otherOpts.add(opt);
      }
    }

    final buttons = <Widget>[];

    // Primary action: [允许]
    for (final opt in allowOpts.take(1)) {
      buttons.add(
        SizedBox(
          width: double.infinity,
          child: Material(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => onSelect(opt.optionId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '允许',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFontSize.base,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Secondary action: [拒绝]
    for (final opt in denyOpts.take(1)) {
      buttons.add(const SizedBox(height: AppSpacing.sm));
      buttons.add(
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withAlpha(80)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            onPressed: () => onSelect(opt.optionId),
            child: const Text('拒绝', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    // Remaining options as plain text buttons
    for (final opt in [...allowOpts.skip(1), ...denyOpts.skip(1), ...otherOpts]) {
      buttons.add(const SizedBox(height: AppSpacing.sm));
      buttons.add(
        SizedBox(
          width: double.infinity,
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.foregroundM(context),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: () => onSelect(opt.optionId),
            child: Text(opt.name, style: const TextStyle(fontSize: AppFontSize.sm)),
          ),
        ),
      );
    }

    return buttons;
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseCommand();
    final riskLevel = _classifyRisk(parsed.command);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Text('权限请求', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),

          // Row: risk chip + tool name
          Row(
            children: [
              _buildRiskChip(parsed.toolName, riskLevel),
              if (parsed.toolName.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  parsed.toolName,
                  style: TextStyle(
                    fontSize: AppFontSize.sm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foregroundM(context),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Command block with horizontal scroll and copy
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              color: AppColors.terminalBg,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      parsed.command,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppColors.terminalFg,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: parsed.command));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制到剪贴板'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.copy, size: 14, color: AppColors.terminalFg.withAlpha(180)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Arguments list (if non-empty)
          if (parsed.arguments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.foregroundM(context).withAlpha(10),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in parsed.arguments.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e.key}: ',
                            style: TextStyle(
                              fontSize: AppFontSize.xs,
                              fontWeight: FontWeight.w600,
                              color: AppColors.foregroundM(context),
                              fontFamily: 'monospace',
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.value,
                              style: TextStyle(
                                fontSize: AppFontSize.xs,
                                color: AppColors.foregroundM(context),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),

          // Action buttons
          ..._buildActionButtons(context),
        ],
      ),
    );
  }
}
