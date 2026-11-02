import 'launch_security_policy.dart';
import 'team_config.dart';

class SessionPreferences {
  SessionPreferences({
    Map<String, String> cliExecutablePaths = const {},
    Map<String, String> toolchainPaths = const {},
    Map<String, String> acpAdapterPaths = const {},
    Map<String, bool> personalAcpDefaults = const {},
    this.defaultSshWorkingDirectory = '',
    this.sshUseLoginShell = false,
    this.autoLaunchAllMembersOnConnect = false,
    this.reclaimIdleTerminals = true,
    this.reclaimIdleTerminalAfterSeconds = 180,
    this.gitAutoFetchEnabled = true,
    this.gitAutoFetchIntervalMinutes = 5,
    this.scopeSessionsToSelectedTeam = true,
    this.terminalScrollbackLines = 10000,
    this.terminalLinkClickOpensInApp = true,
    this.notifyOnSessionIdle = true,
    this.openExistingSessionStartsTerminal = false,
    this.chatSubmitSwitchesToTerminal = false,
    this.acpPermissionDefault = LaunchSecurityPolicy.fullAccess,
  }) : cliExecutablePaths = Map.unmodifiable(
         _normalizeCliExecutablePaths(cliExecutablePaths),
       ),
       toolchainPaths = Map.unmodifiable(
         _normalizeCliExecutablePaths(toolchainPaths),
       ),
       acpAdapterPaths = Map.unmodifiable(
         _normalizeCliExecutablePaths(acpAdapterPaths),
       ),
       personalAcpDefaults = Map.unmodifiable(personalAcpDefaults);

  /// Well-known keys for [toolchainPaths].
  static const toolchainGit = 'git';
  static const toolchainNode = 'node';

  factory SessionPreferences.fromJson(Map<String, Object?> json) {
    return SessionPreferences(
      cliExecutablePaths: _cliExecutablePathsFromJson(
        json['cliExecutablePaths'],
      ),
      acpAdapterPaths: _cliExecutablePathsFromJson(json['acpAdapterPaths']),
      toolchainPaths: _cliExecutablePathsFromJson(json['toolchainPaths']),
      defaultSshWorkingDirectory:
          json['defaultSshWorkingDirectory'] as String? ?? '',
      sshUseLoginShell: json['sshUseLoginShell'] as bool? ?? false,
      autoLaunchAllMembersOnConnect:
          json['autoLaunchAllMembersOnConnect'] as bool? ?? false,
      reclaimIdleTerminals: json['reclaimIdleTerminals'] as bool? ?? true,
      reclaimIdleTerminalAfterSeconds:
          (json['reclaimIdleTerminalAfterSeconds'] as num?)?.toInt() ?? 180,
      gitAutoFetchEnabled: json['gitAutoFetchEnabled'] as bool? ?? true,
      gitAutoFetchIntervalMinutes:
          (json['gitAutoFetchIntervalMinutes'] as num?)?.toInt() ?? 5,
      scopeSessionsToSelectedTeam:
          json['scopeSessionsToSelectedTeam'] as bool? ?? true,
      terminalScrollbackLines:
          (json['terminalScrollbackLines'] as num?)?.toInt() ?? 10000,
      terminalLinkClickOpensInApp:
          json['terminalLinkClickOpensInApp'] as bool? ?? true,
      notifyOnSessionIdle: json['notifyOnSessionIdle'] as bool? ?? true,
      openExistingSessionStartsTerminal:
          json['openExistingSessionStartsTerminal'] as bool? ?? false,
      chatSubmitSwitchesToTerminal:
          json['chatSubmitSwitchesToTerminal'] as bool? ?? false,
      personalAcpDefaults: _personalAcpDefaultsFromJson(json),
      acpPermissionDefault: acpPermissionFromJson(json['acpPermissionDefault']),
    );
  }

  /// CLI executable paths keyed by [CliTool.value]. Empty value means fall
  /// back to startup discovery, then the tool name on PATH.
  final Map<String, String> cliExecutablePaths;

  /// ACP adapter executable paths keyed by [CliTool.value]. Empty value means
  /// fall back to startup discovery.
  final Map<String, String> acpAdapterPaths;

  /// Toolchain executable paths keyed by toolchain constant (e.g.
  /// [toolchainGit], [toolchainNode]). Empty value means the tool is not
  /// configured — callers should fall back to PATH lookup.
  final Map<String, String> toolchainPaths;

  /// Default remote working directory used when an SSH launch has no workspace
  /// path yet. Empty means "do not cd before launching".
  final String defaultSshWorkingDirectory;

  /// When true, SSH launches run through `bash -lc` so remote shell startup
  /// files can populate PATH and related environment.
  final bool sshUseLoginShell;

  /// When true, connecting or restarting the shell session starts every valid
  /// team member instead of only the selected one. Default false (lazy spawn).
  final bool autoLaunchAllMembersOnConnect;

  /// When true, idle member/session terminals are reclaimed after
  /// [reclaimIdleTerminalAfterSeconds] to free memory; they reconnect on demand.
  final bool reclaimIdleTerminals;

  /// Seconds a terminal may sit idle before [reclaimIdleTerminals] reclaims it.
  /// Runtime-configurable so integration tests can run with a few seconds.
  final int reclaimIdleTerminalAfterSeconds;

  /// When true (default), the source-control panel periodically runs a
  /// non-interactive `git fetch --all --prune` for the repository it shows.
  final bool gitAutoFetchEnabled;

  /// Minutes between auto-fetch ticks. UI offers 1 / 5 / 15.
  final int gitAutoFetchIntervalMinutes;

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

  /// When true, show an OS notification when a session leaves the working state.
  final bool notifyOnSessionIdle;

  /// When true, opening an existing conversation from the sidebar/search/deep
  /// link connects the PTY immediately. When false (default), the session opens
  /// in history-review mode until the user submits from slim compose.
  final bool openExistingSessionStartsTerminal;

  /// When true, submitting from Chat switches to the terminal view.
  /// When false (default), stay on Chat while the terminal runs in the
  /// background.
  final bool chatSubmitSwitchesToTerminal;

  /// New-session ACP defaults keyed by [CliTool.value] (the JSON key keeps its
  /// legacy `personalAcpDefaults` name). Missing key means "launch new sessions
  /// as ACP" — controlled from the CLI card's transport pill; existing sessions
  /// keep the runtime they were started with.
  final Map<String, bool> personalAcpDefaults;

  /// Default ACP compose permission for new personal ACP launches and new
  /// mixed ACP seats. Missing JSON key → [LaunchSecurityPolicy.fullAccess].
  final LaunchSecurityPolicy acpPermissionDefault;

  String cliExecutablePathFor(String toolId) =>
      cliExecutablePaths[toolId]?.trim() ?? '';

  String acpAdapterPathFor(String toolId) =>
      acpAdapterPaths[toolId]?.trim() ?? '';

  /// Whether new sessions for [cli] launch as ACP chat.
  bool acpDefaultFor(CliTool cli) => personalAcpDefaults[cli.value] ?? true;

  SessionPreferences withAcpDefault(CliTool cli, bool value) =>
      copyWith(personalAcpDefaults: {...personalAcpDefaults, cli.value: value});

  SessionPreferences copyWith({
    Map<String, String>? cliExecutablePaths,
    Map<String, String>? acpAdapterPaths,
    Map<String, String>? toolchainPaths,
    Map<String, bool>? personalAcpDefaults,
    String? defaultSshWorkingDirectory,
    bool? sshUseLoginShell,
    bool? autoLaunchAllMembersOnConnect,
    bool? reclaimIdleTerminals,
    int? reclaimIdleTerminalAfterSeconds,
    bool? gitAutoFetchEnabled,
    int? gitAutoFetchIntervalMinutes,
    bool? scopeSessionsToSelectedTeam,
    int? terminalScrollbackLines,
    bool? terminalLinkClickOpensInApp,
    bool? notifyOnSessionIdle,
    bool? openExistingSessionStartsTerminal,
    bool? chatSubmitSwitchesToTerminal,
    LaunchSecurityPolicy? acpPermissionDefault,
  }) {
    return SessionPreferences(
      cliExecutablePaths: cliExecutablePaths ?? this.cliExecutablePaths,
      acpAdapterPaths: acpAdapterPaths ?? this.acpAdapterPaths,
      toolchainPaths: toolchainPaths ?? this.toolchainPaths,
      defaultSshWorkingDirectory:
          defaultSshWorkingDirectory ?? this.defaultSshWorkingDirectory,
      sshUseLoginShell: sshUseLoginShell ?? this.sshUseLoginShell,
      autoLaunchAllMembersOnConnect:
          autoLaunchAllMembersOnConnect ?? this.autoLaunchAllMembersOnConnect,
      reclaimIdleTerminals: reclaimIdleTerminals ?? this.reclaimIdleTerminals,
      reclaimIdleTerminalAfterSeconds:
          reclaimIdleTerminalAfterSeconds ??
          this.reclaimIdleTerminalAfterSeconds,
      gitAutoFetchEnabled: gitAutoFetchEnabled ?? this.gitAutoFetchEnabled,
      gitAutoFetchIntervalMinutes:
          gitAutoFetchIntervalMinutes ?? this.gitAutoFetchIntervalMinutes,
      scopeSessionsToSelectedTeam:
          scopeSessionsToSelectedTeam ?? this.scopeSessionsToSelectedTeam,
      terminalScrollbackLines:
          terminalScrollbackLines ?? this.terminalScrollbackLines,
      terminalLinkClickOpensInApp:
          terminalLinkClickOpensInApp ?? this.terminalLinkClickOpensInApp,
      notifyOnSessionIdle: notifyOnSessionIdle ?? this.notifyOnSessionIdle,
      openExistingSessionStartsTerminal:
          openExistingSessionStartsTerminal ??
          this.openExistingSessionStartsTerminal,
      chatSubmitSwitchesToTerminal:
          chatSubmitSwitchesToTerminal ?? this.chatSubmitSwitchesToTerminal,
      personalAcpDefaults: personalAcpDefaults ?? this.personalAcpDefaults,
      acpPermissionDefault: acpPermissionDefault ?? this.acpPermissionDefault,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cliExecutablePaths': cliExecutablePaths,
      'acpAdapterPaths': acpAdapterPaths,
      'toolchainPaths': toolchainPaths,
      'defaultSshWorkingDirectory': defaultSshWorkingDirectory,
      'sshUseLoginShell': sshUseLoginShell,
      'autoLaunchAllMembersOnConnect': autoLaunchAllMembersOnConnect,
      'reclaimIdleTerminals': reclaimIdleTerminals,
      'reclaimIdleTerminalAfterSeconds': reclaimIdleTerminalAfterSeconds,
      'gitAutoFetchEnabled': gitAutoFetchEnabled,
      'gitAutoFetchIntervalMinutes': gitAutoFetchIntervalMinutes,
      'scopeSessionsToSelectedTeam': scopeSessionsToSelectedTeam,
      'terminalScrollbackLines': terminalScrollbackLines,
      'terminalLinkClickOpensInApp': terminalLinkClickOpensInApp,
      'notifyOnSessionIdle': notifyOnSessionIdle,
      'openExistingSessionStartsTerminal': openExistingSessionStartsTerminal,
      'chatSubmitSwitchesToTerminal': chatSubmitSwitchesToTerminal,
      'personalAcpDefaults': personalAcpDefaults,
      if (acpPermissionToJson(acpPermissionDefault) case final id?)
        'acpPermissionDefault': id,
    };
  }

  /// Older builds stored each CLI's default as its own boolean key.
  static const Map<String, String> _legacyPersonalAcpKeys = {
    'claude': 'claudePersonalAcpDefault',
    'codex': 'codexPersonalAcpDefault',
    'cursor': 'cursorPersonalAcpDefault',
    'opencode': 'opencodePersonalAcpDefault',
  };

  static Map<String, bool> _personalAcpDefaultsFromJson(
    Map<String, Object?> json,
  ) {
    final raw = json['personalAcpDefaults'];
    if (raw is Map) {
      return {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is bool)
            entry.key as String: entry.value as bool,
      };
    }
    return {
      for (final entry in _legacyPersonalAcpKeys.entries)
        if (json[entry.value] case final bool value) entry.key: value,
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
