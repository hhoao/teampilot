import 'package:flutter/foundation.dart';

/// Built-in `--agent` ids (subset of `flashskyai agents` / CLI presets).
@immutable
class FlashskyBuiltInAgentEntry {
  const FlashskyBuiltInAgentEntry({
    required this.id,
    required this.modelHintEn,
    required this.modelHintZh,
  });

  final String id;
  final String modelHintEn;
  final String modelHintZh;
}

abstract final class FlashskyBuiltInAgents {
  FlashskyBuiltInAgents._();

  /// Dropdown sentinel: clear `--agent`.
  static const noneDropdownValue = '__fsk_agent_none__';

  /// Dropdown sentinel: free-text `--agent` id.
  static const customDropdownValue = '__fsk_agent_custom__';

  static const List<FlashskyBuiltInAgentEntry> builtIns = [
    FlashskyBuiltInAgentEntry(
      id: 'flashskyai-code-guide',
      modelHintEn: 'haiku',
      modelHintZh: 'haiku',
    ),
    FlashskyBuiltInAgentEntry(
      id: 'general-purpose',
      modelHintEn: 'inherit',
      modelHintZh: 'inherit',
    ),
    FlashskyBuiltInAgentEntry(
      id: 'statusline-setup',
      modelHintEn: 'sonnet',
      modelHintZh: 'sonnet',
    ),
  ];

  static FlashskyBuiltInAgentEntry? tryParseBuiltinId(String id) {
    for (final e in builtIns) {
      if (e.id == id) return e;
    }
    return null;
  }

  static List<String> dropdownValues() => [
    noneDropdownValue,
    ...builtIns.map((e) => e.id),
    customDropdownValue,
  ];

  static String activeDropdownValue(String agent) {
    final t = agent.trim();
    if (t.isEmpty) return noneDropdownValue;
    if (tryParseBuiltinId(t) != null) return t;
    return customDropdownValue;
  }
}
