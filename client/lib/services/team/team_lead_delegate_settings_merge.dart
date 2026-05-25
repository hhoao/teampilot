

/// Merges team-lead delegate-only PreToolUse hook into Claude Code settings.
class TeamLeadDelegateSettingsMerge {
  const TeamLeadDelegateSettingsMerge();

  static const marker = 'teampilot-team-lead-delegate-only';

  /// Pipe-separated PreToolUse matcher (Claude Code hook syntax).
  static const blockedToolsMatcher =
      'Bash|Edit|Write|NotebookEdit|PowerShell|Skill|ExecuteExtraTool|REPL|workflow|EnterWorktree|ExitWorktree|RemoteTrigger|CronCreate';

  Map<String, Object?> mergeIntoSettings({
    required Map<String, Object?> base,
    required String hookCommand,
  }) {
    if (!_isHookPresent(base, hookCommand)) {
      final hooks = Map<String, Object?>.from(
        (base['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
      );
      final existing = List<Object?>.from(
        (hooks['PreToolUse'] as List?) ?? const [],
      );
      hooks['PreToolUse'] = <Object?>[
        ...existing,
        _preToolUseEntry(hookCommand),
      ];
      return {...base, 'hooks': hooks};
    }
    return base;
  }

  /// Removes delegate-only hook entries (e.g. when the team toggle is off).
  Map<String, Object?> stripFromSettings(Map<String, Object?> base) {
    final hooks = base['hooks'];
    if (hooks is! Map) return base;

    final pre = hooks['PreToolUse'];
    if (pre is! List || pre.isEmpty) return base;

    final filtered = <Object?>[
      for (final entry in pre)
        if (!_entryHasMarker(entry)) entry,
    ];
    if (filtered.length == pre.length) return base;

    final nextHooks = Map<String, Object?>.from(hooks.cast<String, Object?>());
    if (filtered.isEmpty) {
      nextHooks.remove('PreToolUse');
    } else {
      nextHooks['PreToolUse'] = filtered;
    }
    if (nextHooks.isEmpty) {
      final merged = Map<String, Object?>.from(base);
      merged.remove('hooks');
      return merged;
    }
    return {...base, 'hooks': nextHooks};
  }

  bool _isHookPresent(Map<String, Object?> base, String hookCommand) {
    final pre = (base['hooks'] as Map?)?['PreToolUse'];
    if (pre is! List) return false;
    for (final entry in pre) {
      if (_entryHasMarker(entry)) return true;
    }
    return false;
  }

  bool _entryHasMarker(Object? entry) {
    if (entry is! Map) return false;
    final inner = entry['hooks'];
    if (inner is! List) return false;
    for (final h in inner) {
      if (h is Map) {
        final command = h['command']?.toString() ?? '';
        if (command.contains(marker)) return true;
      }
    }
    return false;
  }

  Map<String, Object?> _preToolUseEntry(String hookCommand) => {
    'matcher': blockedToolsMatcher,
    'hooks': [
      {'type': 'command', 'command': hookCommand},
    ],
  };
}
