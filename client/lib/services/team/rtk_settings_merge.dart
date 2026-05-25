

/// Merges RTK PreToolUse hook entries into Claude Code-compatible settings.
class RtkSettingsMerge {
  const RtkSettingsMerge();

  static const _rtkMarker = 'rtk-rewrite';

  Map<String, Object?> mergeIntoSettings({
    required Map<String, Object?> base,
    required String hookCommand,
  }) {
    if (_hasRtkHook(base)) return base;

    final fragment = _rtkPreToolUseEntry(hookCommand);
    final hooks = Map<String, Object?>.from(
      (base['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final existing = List<Object?>.from(
      (hooks['PreToolUse'] as List?) ?? const [],
    );
    hooks['PreToolUse'] = <Object?>[fragment, ...existing];
    return {...base, 'hooks': hooks};
  }

  bool _hasRtkHook(Map<String, Object?> base) {
    final pre = (base['hooks'] as Map?)?['PreToolUse'];
    if (pre is! List) return false;
    for (final entry in pre) {
      if (entry is! Map) continue;
      final inner = entry['hooks'];
      if (inner is! List) continue;
      for (final h in inner) {
        if (h is Map) {
          final command = h['command']?.toString() ?? '';
          if (command.contains(_rtkMarker)) return true;
        }
      }
    }
    return false;
  }

  Map<String, Object?> _rtkPreToolUseEntry(String hookCommand) => {
    'matcher': 'Bash',
    'hooks': [
      {'type': 'command', 'command': hookCommand},
    ],
  };
}
