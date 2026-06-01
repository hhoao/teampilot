/// Merges a `{event → [{matcher, hooks:[{type:command, command}]}]}` hook
/// entry into Claude Code-compatible settings, idempotent by [marker].
///
/// Generalizes the former `RtkSettingsMerge` (event/matcher/marker were fixed
/// to `PreToolUse` / `Bash` / `rtk-rewrite`).
class SettingsHookEffectApplier {
  const SettingsHookEffectApplier();

  Map<String, Object?> mergeIntoSettings({
    required Map<String, Object?> base,
    required String event,
    required String matcher,
    required String hookCommand,
    required String marker,
  }) {
    if (_hasMarkedHook(base, event, marker)) return base;

    final fragment = <String, Object?>{
      'matcher': matcher,
      'hooks': [
        {'type': 'command', 'command': hookCommand},
      ],
    };
    final hooks = Map<String, Object?>.from(
      (base['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final existing = List<Object?>.from((hooks[event] as List?) ?? const []);
    hooks[event] = <Object?>[fragment, ...existing];
    return {...base, 'hooks': hooks};
  }

  bool _hasMarkedHook(Map<String, Object?> base, String event, String marker) {
    final entries = (base['hooks'] as Map?)?[event];
    if (entries is! List) return false;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final inner = entry['hooks'];
      if (inner is! List) continue;
      for (final h in inner) {
        if (h is Map) {
          final command = h['command']?.toString() ?? '';
          if (command.contains(marker)) return true;
        }
      }
    }
    return false;
  }
}
