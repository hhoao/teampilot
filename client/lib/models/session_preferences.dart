import 'connection_mode.dart';
import 'windows_storage_backend.dart';
import '../services/app/platform_utils.dart';

class SessionPreferences {
  SessionPreferences({
    ConnectionMode? connectionMode,
    Map<String, String> cliExecutablePaths = const {},
    Map<String, String> toolchainPaths = const {},
    this.defaultSshWorkingDirectory = '',
    this.sshUseLoginShell = false,
    this.autoLaunchAllMembersOnConnect = true,
    this.scopeSessionsToSelectedTeam = true,
    this.terminalScrollbackLines = 10000,
    this.terminalLinkClickOpensInApp = true,
    WindowsStorageBackend? windowsStorageBackend,
  }) : connectionMode = connectionMode ?? defaultConnectionMode(),
       windowsStorageBackend =
           windowsStorageBackend ?? WindowsStorageBackend.native,
       cliExecutablePaths = Map.unmodifiable(
         _normalizeCliExecutablePaths(cliExecutablePaths),
       ),
       toolchainPaths = Map.unmodifiable(
         _normalizeCliExecutablePaths(toolchainPaths),
       );

  /// Well-known keys for [toolchainPaths].
  static const toolchainGit = 'git';
  static const toolchainNode = 'node';

  factory SessionPreferences.fromJson(Map<String, Object?> json) {
    return SessionPreferences(
      connectionMode: ConnectionModeJson.fromJson(
        json['connectionMode'] as String?,
        fallback: defaultConnectionMode(),
      ),
      cliExecutablePaths: _cliExecutablePathsFromJson(
        json['cliExecutablePaths'],
      ),
      toolchainPaths: _cliExecutablePathsFromJson(
        json['toolchainPaths'],
      ),
      defaultSshWorkingDirectory:
          json['defaultSshWorkingDirectory'] as String? ?? '',
      sshUseLoginShell: json['sshUseLoginShell'] as bool? ?? false,
      autoLaunchAllMembersOnConnect:
          json['autoLaunchAllMembersOnConnect'] as bool? ?? true,
      scopeSessionsToSelectedTeam:
          json['scopeSessionsToSelectedTeam'] as bool? ?? true,
      terminalScrollbackLines:
          (json['terminalScrollbackLines'] as num?)?.toInt() ?? 10000,
      terminalLinkClickOpensInApp:
          json['terminalLinkClickOpensInApp'] as bool? ?? true,
      windowsStorageBackend: WindowsStorageBackendJson.fromJson(
        json['windowsStorageBackend'] as String?,
      ),
    );
  }

  /// Local PTY vs remote SSH transport for launching [flashskyai].
  final ConnectionMode connectionMode;

  /// CLI executable paths keyed by [CliTool.value]. Empty value means fall
  /// back to startup discovery, then the tool name on PATH.
  final Map<String, String> cliExecutablePaths;

  /// Toolchain executable paths keyed by toolchain constant (e.g.
  /// [toolchainGit], [toolchainNode]). Empty value means the tool is not
  /// configured — callers should fall back to PATH lookup.
  final Map<String, String> toolchainPaths;

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

  /// Maximum scrollback lines retained per embedded terminal session.
  final int terminalScrollbackLines;

  /// When true, a plain left-click on a link/file-path in the embedded terminal
  /// is handled in-app (open in editor / TeamPilot's URI opener) instead of
  /// being forwarded to the running program (which may launch an external app).
  /// Ctrl/Cmd-click always opens in-app regardless of this setting.
  final bool terminalLinkClickOpensInApp;

  /// Windows-only: business file I/O via native AppData or WSL home.
  final WindowsStorageBackend windowsStorageBackend;

  String cliExecutablePathFor(String toolId) =>
      cliExecutablePaths[toolId]?.trim() ?? '';

  SessionPreferences copyWith({
    ConnectionMode? connectionMode,
    Map<String, String>? cliExecutablePaths,
    Map<String, String>? toolchainPaths,
    String? defaultSshWorkingDirectory,
    bool? sshUseLoginShell,
    bool? autoLaunchAllMembersOnConnect,
    bool? scopeSessionsToSelectedTeam,
    int? terminalScrollbackLines,
    bool? terminalLinkClickOpensInApp,
    WindowsStorageBackend? windowsStorageBackend,
  }) {
    return SessionPreferences(
      connectionMode: connectionMode ?? this.connectionMode,
      cliExecutablePaths: cliExecutablePaths ?? this.cliExecutablePaths,
      toolchainPaths: toolchainPaths ?? this.toolchainPaths,
      defaultSshWorkingDirectory:
          defaultSshWorkingDirectory ?? this.defaultSshWorkingDirectory,
      sshUseLoginShell: sshUseLoginShell ?? this.sshUseLoginShell,
      autoLaunchAllMembersOnConnect:
          autoLaunchAllMembersOnConnect ?? this.autoLaunchAllMembersOnConnect,
      scopeSessionsToSelectedTeam:
          scopeSessionsToSelectedTeam ?? this.scopeSessionsToSelectedTeam,
      terminalScrollbackLines:
          terminalScrollbackLines ?? this.terminalScrollbackLines,
      terminalLinkClickOpensInApp:
          terminalLinkClickOpensInApp ?? this.terminalLinkClickOpensInApp,
      windowsStorageBackend:
          windowsStorageBackend ?? this.windowsStorageBackend,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'connectionMode': connectionMode.toJson(),
      'cliExecutablePaths': cliExecutablePaths,
      'toolchainPaths': toolchainPaths,
      'defaultSshWorkingDirectory': defaultSshWorkingDirectory,
      'sshUseLoginShell': sshUseLoginShell,
      'autoLaunchAllMembersOnConnect': autoLaunchAllMembersOnConnect,
      'scopeSessionsToSelectedTeam': scopeSessionsToSelectedTeam,
      'terminalScrollbackLines': terminalScrollbackLines,
      'terminalLinkClickOpensInApp': terminalLinkClickOpensInApp,
      'windowsStorageBackend': windowsStorageBackend.toJson(),
    };
  }

  static Map<String, String> _cliExecutablePathsFromJson(Object? value) {
    if (value is! Map) return const {};
    return _normalizeCliExecutablePaths(
      value.map(
        (key, value) =>
            MapEntry(key is String ? key : '', value is String ? value : ''),
      ),
    );
  }

  static Map<String, String> _normalizeCliExecutablePaths(
    Map<String, String> paths,
  ) {
    final normalized = <String, String>{};
    for (final entry in paths.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;
      normalized[key] = value;
    }
    return normalized;
  }
}
