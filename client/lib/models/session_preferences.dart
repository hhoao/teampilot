class SessionPreferences {
  const SessionPreferences({
    this.cliExecutablePath = '',
    this.autoLaunchAllMembersOnConnect = false,
    this.scopeSessionsToSelectedTeam = false,
  });

  factory SessionPreferences.fromJson(Map<String, Object?> json) {
    return SessionPreferences(
      cliExecutablePath: json['cliExecutablePath'] as String? ?? '',
      autoLaunchAllMembersOnConnect:
          json['autoLaunchAllMembersOnConnect'] as bool? ?? true,
      scopeSessionsToSelectedTeam:
          json['scopeSessionsToSelectedTeam'] as bool? ?? true,
    );
  }

  /// Absolute path to the flashskyai CLI executable. Empty means "fall back
  /// to the path located at startup, then to bare 'flashskyai' (resolved by
  /// the OS via PATH)".
  final String cliExecutablePath;

  /// When true, connecting or restarting the shell session starts every valid
  /// team member instead of only the selected one.
  final bool autoLaunchAllMembersOnConnect;

  /// When true, the sidebar lists only sessions whose [AppSession.sessionTeam]
  /// matches the selected team id.
  final bool scopeSessionsToSelectedTeam;

  SessionPreferences copyWith({
    String? cliExecutablePath,
    bool? autoLaunchAllMembersOnConnect,
    bool? scopeSessionsToSelectedTeam,
  }) {
    return SessionPreferences(
      cliExecutablePath: cliExecutablePath ?? this.cliExecutablePath,
      autoLaunchAllMembersOnConnect:
          autoLaunchAllMembersOnConnect ?? this.autoLaunchAllMembersOnConnect,
      scopeSessionsToSelectedTeam:
          scopeSessionsToSelectedTeam ?? this.scopeSessionsToSelectedTeam,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'cliExecutablePath': cliExecutablePath,
      'autoLaunchAllMembersOnConnect': autoLaunchAllMembersOnConnect,
      'scopeSessionsToSelectedTeam': scopeSessionsToSelectedTeam,
    };
  }
}
