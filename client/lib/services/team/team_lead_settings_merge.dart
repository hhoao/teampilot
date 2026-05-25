

/// Merges team-lead PreToolUse hook entries into Claude Code settings.
class TeamLeadSettingsMerge {
  const TeamLeadSettingsMerge();

  static const _marker = 'teampilot-deny-team-lead-self-message';

  /// PreToolUse matchers for team-lead coordination hooks (same script).
  static const guardedTools = ['SendMessage', 'TaskUpdate', 'Agent'];

  Map<String, Object?> mergeIntoSettings({
    required Map<String, Object?> base,
    required String hookCommand,
  }) {
    final missing = _missingGuardedMatchers(base);
    if (missing.isEmpty) return base;

    final hooks = Map<String, Object?>.from(
      (base['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final existing = List<Object?>.from(
      (hooks['PreToolUse'] as List?) ?? const [],
    );
    final fragments = [
      for (final tool in missing) _preToolUseEntry(hookCommand, tool),
    ];
    hooks['PreToolUse'] = <Object?>[...existing, ...fragments];
    return {...base, 'hooks': hooks};
  }

  List<String> _missingGuardedMatchers(Map<String, Object?> base) {
    final pre = (base['hooks'] as Map?)?['PreToolUse'];
    if (pre is! List) return List<String>.from(guardedTools);

    final covered = <String>{};
    for (final entry in pre) {
      if (entry is! Map) continue;
      final matcher = entry['matcher']?.toString();
      if (matcher == null || !guardedTools.contains(matcher)) continue;
      final inner = entry['hooks'];
      if (inner is! List) continue;
      for (final h in inner) {
        if (h is Map) {
          final command = h['command']?.toString() ?? '';
          if (command.contains(_marker)) {
            covered.add(matcher);
            break;
          }
        }
      }
    }
    return [
      for (final tool in guardedTools)
        if (!covered.contains(tool)) tool,
    ];
  }

  Map<String, Object?> _preToolUseEntry(String hookCommand, String matcher) => {
    'matcher': matcher,
    'hooks': [
      {'type': 'command', 'command': hookCommand},
    ],
  };
}
