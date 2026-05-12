class SessionPreferences {
  const SessionPreferences({
    this.cliExecutablePath = '',
    this.autoLaunchAllMembersOnConnect = false,
  });

  factory SessionPreferences.fromJson(Map<String, Object?> json) {
    return SessionPreferences(
      cliExecutablePath: json['cliExecutablePath'] as String? ?? '',
      autoLaunchAllMembersOnConnect:
          json['autoLaunchAllMembersOnConnect'] as bool? ?? false,
    );
  }

  /// Absolute path to the flashskyai CLI executable. Empty means "fall back
  /// to the path located at startup, then to bare 'flashskyai' (resolved by
  /// the OS via PATH)".
  final String cliExecutablePath;

  /// When true, connecting or restarting the shell session starts every valid
  /// team member instead of only the selected one.
  final bool autoLaunchAllMembersOnConnect;

  SessionPreferences copyWith({
    String? cliExecutablePath,
    bool? autoLaunchAllMembersOnConnect,
  }) {
    return SessionPreferences(
      cliExecutablePath: cliExecutablePath ?? this.cliExecutablePath,
      autoLaunchAllMembersOnConnect:
          autoLaunchAllMembersOnConnect ?? this.autoLaunchAllMembersOnConnect,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'cliExecutablePath': cliExecutablePath,
      'autoLaunchAllMembersOnConnect': autoLaunchAllMembersOnConnect,
    };
  }
}
