import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders the official brand vector logo for AI Agents
/// (OpenCode, Codex, Claude, Gemini, OMP).
///
/// SVG assets are taken from each agent's official website:
/// - OpenCode:  anomalyco/opencode brand assets (opencode.ai)
/// - Codex:     openai.com header logo (OpenAI knot)
/// - Claude:    claude.ai favicon (Anthropic asterisk)
/// - Gemini:    gstatic.com official sparkle
/// - OMP:       omp.sh favicon
class AgentLogo extends StatelessWidget {
  final String? agentName;
  final double size;
  final Color? color;

  const AgentLogo({
    super.key,
    required this.agentName,
    this.size = 18,
    this.color,
  });

  /// 单色官方资产：渲染时染主题色（color 参数）。
  static const Map<String, String> _monoAssets = {
    'codex': 'assets/logos/openai_knot.svg',
    'openai': 'assets/logos/openai_knot.svg',
    'claude': 'assets/logos/anthropic_star.svg',
    'anthropic': 'assets/logos/anthropic_star.svg',
  };

  /// 多色/官方配色的资产：原样渲染（不染色）。
  static const Map<String, String> _brandAssets = {
    'opencode': 'assets/logos/opencode_square.svg',
    'gemini': 'assets/logos/gemini_sparkle.svg',
    'omp': 'assets/logos/omp.svg',
    'oh my pi': 'assets/logos/omp.svg',
  };

  static String? _match(Map<String, String> table, String name) {
    for (final entry in table.entries) {
      if (name.contains(entry.key)) return entry.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = (agentName ?? '').toLowerCase().trim();
    final logoColor = color ?? Theme.of(context).textTheme.bodyMedium?.color ?? Colors.white;

    final monoAsset = _match(_monoAssets, name);
    final brandAsset = monoAsset == null ? _match(_brandAssets, name) : null;
    final asset = monoAsset ?? brandAsset;
    if (asset == null) {
      return _FallbackLogo(name: name, size: size, color: logoColor);
    }

    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: monoAsset != null ? ColorFilter.mode(logoColor, BlendMode.srcIn) : null,
    );
  }
}

/// 未匹配到已知 agent 时的占位：浅色圆底 + 首字母。
class _FallbackLogo extends StatelessWidget {
  final String name;
  final double size;
  final Color color;

  const _FallbackLogo({required this.name, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
