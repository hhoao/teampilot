import 'connection_mode.dart';
import '../services/platform_utils.dart';

class SessionPreferences {
  SessionPreferences({
    ConnectionMode? connectionMode,
    this.cliExecutablePath = '',
    this.defaultSshWorkingDirectory = '',
    this.sshUseLoginShell = false,
    this.autoLaunchAllMembersOnConnect = true,
    this.scopeSessionsToSelectedTeam = true,
  }) : connectionMode = connectionMode ?? defaultConnectionMode();

  factory SessionPreferences.fromJson(Map<String, Object?> json) {
    return SessionPreferences(
      connectionMode: ConnectionModeJson.fromJson(
        json['connectionMode'] as String?,
        fallback: defaultConnectionMode(),
      ),
      cliExecutablePath: json['cliExecutablePath'] as String? ?? '',
      defaultSshWorkingDirectory:
          json['defaultSshWorkingDirectory'] as String? ?? '',
      sshUseLoginShell: json['sshUseLoginShell'] as bool? ?? false,
      autoLaunchAllMembersOnConnect:
          json['autoLaunchAllMembersOnConnect'] as bool? ?? true,
      scopeSessionsToSelectedTeam:
          json['scopeSessionsToSelectedTeam'] as bool? ?? true,
    );
  }

  /// Local PTY vs remote SSH transport for launching [flashskyai].
  final ConnectionMode connectionMode;

  /// Absolute path to the flashskyai CLI executable. Empty means "fall back
  /// to the path located at startup, then to bare 'flashskyai' (resolved by
  /// the OS via PATH)".
  ///
  /// In [ConnectionMode.ssh] this is the path on the remote host.
  final String cliExecutablePath;

  /// Default remote working directory used when an SSH launch has no project
  /// path yet. Empty means "do not cd before launching".
  final String defaultSshWorkingDirectory;

  /// When true, SSH launches run through `bash -lc` so remote shell startup
  /// files can populate PATH and related environment.
  final bool sshUseLoginShell;

  /// When true, connecting or restarting the shell session starts every valid
  /// team member instead of only the selected one.
  final bool autoLaunchAllMembersOnConnect;

  /// When true, the sidebar lists only sessions whose [AppSession.sessionTeam]
  /// matches the selected team id.
  final bool scopeSessionsToSelectedTeam;

  SessionPreferences copyWith({
    ConnectionMode? connectionMode,
    String? cliExecutablePath,
    String? defaultSshWorkingDirectory,
    bool? sshUseLoginShell,
    bool? autoLaunchAllMembersOnConnect,
    bool? scopeSessionsToSelectedTeam,
  }) {
    return SessionPreferences(
      connectionMode: connectionMode ?? this.connectionMode,
      cliExecutablePath: cliExecutablePath ?? this.cliExecutablePath,
      defaultSshWorkingDirectory:
          defaultSshWorkingDirectory ?? this.defaultSshWorkingDirectory,
      sshUseLoginShell: sshUseLoginShell ?? this.sshUseLoginShell,
      autoLaunchAllMembersOnConnect:
          autoLaunchAllMembersOnConnect ?? this.autoLaunchAllMembersOnConnect,
      scopeSessionsToSelectedTeam:
          scopeSessionsToSelectedTeam ?? this.scopeSessionsToSelectedTeam,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'connectionMode': connectionMode.toJson(),
      'cliExecutablePath': cliExecutablePath,
      'defaultSshWorkingDirectory': defaultSshWorkingDirectory,
      'sshUseLoginShell': sshUseLoginShell,
      'autoLaunchAllMembersOnConnect': autoLaunchAllMembersOnConnect,
      'scopeSessionsToSelectedTeam': scopeSessionsToSelectedTeam,
    };
  }
}
