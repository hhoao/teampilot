/// Merges team-lead PreToolUse hook entries into Claude Code settings.
class TeamLeadSettingsMerge {
  const TeamLeadSettingsMerge();

  static const _marker = 'teampilot-deny-team-lead-self-message';

  Map<String, Object?> mergeIntoSettings({
    required Map<String, Object?> base,
    required String hookCommand,
  }) {
    if (_hasTeamLeadHook(base)) return base;

    final fragment = _preToolUseEntry(hookCommand);
    final hooks = Map<String, Object?>.from(
      (base['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final existing = List<Object?>.from(
      (hooks['PreToolUse'] as List?) ?? const [],
    );
    hooks['PreToolUse'] = <Object?>[...existing, fragment];
    return {...base, 'hooks': hooks};
  }

  bool _hasTeamLeadHook(Map<String, Object?> base) {
    final pre = (base['hooks'] as Map?)?['PreToolUse'];
    if (pre is! List) return false;
    for (final entry in pre) {
      if (entry is! Map) continue;
      final inner = entry['hooks'];
      if (inner is! List) continue;
      for (final h in inner) {
        if (h is Map) {
          final command = h['command']?.toString() ?? '';
          if (command.contains(_marker)) return true;
        }
      }
    }
    return false;
  }

  Map<String, Object?> _preToolUseEntry(String hookCommand) => {
    'matcher': 'SendMessage',
    'hooks': [
      {'type': 'command', 'command': hookCommand},
    ],
  };
}
