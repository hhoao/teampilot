import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/session_preferences.dart';
import '../services/cli/cli_tool_locator.dart';
import '../services/cli/registry/capabilities/executable_resolver_capability.dart';
import '../services/cli/registry/cli_tool_registry.dart';
import '../models/team_config.dart';
import '../repositories/session_preferences_repository.dart';

class SessionPreferencesState extends Equatable {
  SessionPreferencesState({
    SessionPreferences? preferences,
    this.isLoading = true,
    this.locatedExecutablesRevision = 0,
  }) : preferences = preferences ?? SessionPreferences();

  final SessionPreferences preferences;
  final bool isLoading;

  /// Bumped when startup PATH discovery merges new CLI locations so settings
  /// rows can hide install actions once an executable is known.
  final int locatedExecutablesRevision;

  SessionPreferencesState copyWith({
    SessionPreferences? preferences,
    bool? isLoading,
    int? locatedExecutablesRevision,
  }) {
    return SessionPreferencesState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
      locatedExecutablesRevision:
          locatedExecutablesRevision ?? this.locatedExecutablesRevision,
    );
  }

  @override
  List<Object?> get props => [
    preferences,
    isLoading,
    locatedExecutablesRevision,
  ];
}

class SessionPreferencesCubit extends Cubit<SessionPreferencesState> {
  SessionPreferencesCubit({
    required SessionPreferencesRepository repository,
    Map<CliTool, String> locatedExecutables = const {},
    Map<String, String> locatedToolchains = const {},
    CliToolRegistry? cliToolRegistry,
  }) : _repository = repository,
       _locatedExecutables = _normalizeLocatedExecutables(locatedExecutables),
       _locatedToolchains = _normalizeLocatedToolchains(locatedToolchains),
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry,
       super(SessionPreferencesState());

  static final _defaultCliRegistry = () {
    final r = CliToolRegistry.builtIn();
    return r;
  }();

  final SessionPreferencesRepository _repository;
  final Map<CliTool, String> _locatedExecutables;
  final Map<String, String> _locatedToolchains;
  final CliToolRegistry _cliToolRegistry;

  /// Merges startup PATH discovery; user-configured paths always win.
  void mergeLocatedExecutables(Map<CliTool, String> discovered) {
    var changed = false;
    for (final entry in discovered.entries) {
      final path = entry.value.trim();
      if (path.isEmpty || _userExecutableFor(entry.key).isNotEmpty) continue;
      if (_locatedExecutables[entry.key] == path) continue;
      _locatedExecutables[entry.key] = path;
      changed = true;
    }
    if (changed) {
      emit(
        state.copyWith(
          locatedExecutablesRevision: state.locatedExecutablesRevision + 1,
        ),
      );
    }
  }

  /// Absolute path found at startup for [cli], if any (ignores bare command names).
  String discoveredExecutablePath(CliTool cli) =>
      _locatedExecutables[cli]?.trim() ?? '';

  /// Merges startup PATH discovery for toolchain tools; user paths always win.
  void mergeLocatedToolchains(Map<String, String> discovered) {
    var changed = false;
    for (final entry in discovered.entries) {
      final path = entry.value.trim();
      if (path.isEmpty || toolchainPath(entry.key).isNotEmpty) continue;
      if (_locatedToolchains[entry.key] == path) continue;
      _locatedToolchains[entry.key] = path;
      changed = true;
    }
    if (changed) {
      emit(
        state.copyWith(
          locatedExecutablesRevision: state.locatedExecutablesRevision + 1,
        ),
      );
    }
  }

  /// Absolute path found at startup for toolchain [toolId], if any.
  String discoveredToolchainPath(String toolId) =>
      _locatedToolchains[toolId]?.trim() ?? '';

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final prefs = await _repository.load();
    emit(state.copyWith(preferences: prefs, isLoading: false));
  }

  Future<void> _save(SessionPreferences preferences) async {
    emit(state.copyWith(preferences: preferences));
    await _repository.save(preferences);
  }

  Future<void> setCliExecutablePathFor(CliTool cli, String value) {
    final pathKey =
        _cliToolRegistry
            .capability<ExecutableResolverCapability>(cli)
            ?.preferencesPathKey ??
        cli.value;
    final next = Map<String, String>.of(state.preferences.cliExecutablePaths);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      next.remove(pathKey);
    } else {
      next[pathKey] = trimmed;
    }
    return _save(state.preferences.copyWith(cliExecutablePaths: next));
  }

  /// Persists several CLI executable paths in a single preferences write.
  ///
  /// Empty values are skipped (existing entries are left unchanged).
  Future<void> setCliExecutablePaths(Map<CliTool, String> paths) {
    if (paths.isEmpty) return Future.value();
    final next = Map<String, String>.of(state.preferences.cliExecutablePaths);
    var changed = false;
    for (final entry in paths.entries) {
      final trimmed = entry.value.trim();
      if (trimmed.isEmpty) continue;
      final pathKey =
          _cliToolRegistry
              .capability<ExecutableResolverCapability>(entry.key)
              ?.preferencesPathKey ??
          entry.key.value;
      if (next[pathKey] == trimmed) continue;
      next[pathKey] = trimmed;
      changed = true;
    }
    if (!changed) return Future.value();
    return _save(state.preferences.copyWith(cliExecutablePaths: next));
  }

  /// Returns the stored toolchain executable path for [toolId], or empty.
  String toolchainPath(String toolId) =>
      state.preferences.toolchainPaths[toolId]?.trim() ?? '';

  /// Persists a toolchain executable path keyed by [toolId].
  Future<void> setToolchainPath(String toolId, String path) {
    final next = Map<String, String>.of(state.preferences.toolchainPaths);
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      next.remove(toolId);
    } else {
      next[toolId] = trimmed;
    }
    return _save(state.preferences.copyWith(toolchainPaths: next));
  }

  /// Returns the resolved executable string for a toolchain tool.
  ///
  /// Checks the user-configured [toolchainPath] first, then startup discovery,
  /// then [fallback] (typically the bare command name for PATH lookup).
  String resolveToolchainExecutable(String toolId, String fallback) {
    final configured = toolchainPath(toolId);
    if (configured.isNotEmpty) return configured;
    final located = _locatedToolchains[toolId];
    if (located != null && located.isNotEmpty) return located;
    return fallback;
  }

  Future<void> setDefaultSshWorkingDirectory(String value) {
    return _save(
      state.preferences.copyWith(defaultSshWorkingDirectory: value.trim()),
    );
  }

  Future<void> setSshUseLoginShell(bool value) {
    return _save(state.preferences.copyWith(sshUseLoginShell: value));
  }

  Future<void> setAutoLaunchAllMembersOnConnect(bool value) {
    return _save(
      state.preferences.copyWith(autoLaunchAllMembersOnConnect: value),
    );
  }

  Future<void> setScopeSessionsToSelectedTeam(bool value) {
    return _save(
      state.preferences.copyWith(scopeSessionsToSelectedTeam: value),
    );
  }

  Future<void> setTerminalScrollbackLines(int value) {
    final clamped = value.clamp(1000, 200000);
    return _save(state.preferences.copyWith(terminalScrollbackLines: clamped));
  }

  Future<void> setTerminalLinkClickOpensInApp(bool value) {
    return _save(
      state.preferences.copyWith(terminalLinkClickOpensInApp: value),
    );
  }

  Future<void> setNotifyOnSessionIdle(bool value) {
    return _save(state.preferences.copyWith(notifyOnSessionIdle: value));
  }

  Future<void> setOpenExistingSessionStartsTerminal(bool value) {
    return _save(
      state.preferences.copyWith(openExistingSessionStartsTerminal: value),
    );
  }

  Future<void> setChatSubmitSwitchesToTerminal(bool value) {
    return _save(
      state.preferences.copyWith(chatSubmitSwitchesToTerminal: value),
    );
  }

  Future<void> setSimpleModeDefaultFullAccess(bool value) {
    return _save(
      state.preferences.copyWith(simpleModeDefaultFullAccess: value),
    );
  }

  /// Returns the actual executable string to invoke for [cli]:
  ///   1. user-configured path (if non-empty after trim)
  ///   2. path discovered at startup (if non-null and non-empty)
  ///   3. the CLI's command name (OS resolves via PATH)
  String resolveExecutable([CliTool cli = CliTool.claude]) {
    final user = _userExecutableFor(cli);
    if (user.isNotEmpty) {
      return CliToolLocator.resolveSpawnExecutable(user);
    }
    final located = _locatedExecutables[cli];
    if (located != null && located.isNotEmpty) {
      return CliToolLocator.resolveSpawnExecutable(located);
    }
    final resolver = _cliToolRegistry.capability<ExecutableResolverCapability>(
      cli,
    );
    return resolver?.defaultExecutableName ?? cli.value;
  }

  String _userExecutableFor(CliTool cli) {
    final pathKey =
        _cliToolRegistry
            .capability<ExecutableResolverCapability>(cli)
            ?.preferencesPathKey ??
        cli.value;
    return state.preferences.cliExecutablePathFor(pathKey);
  }

  /// User-configured absolute path for [cli], or empty.
  String configuredExecutablePath(CliTool cli) => _userExecutableFor(cli);

  /// True when [cli] has a configured or discovered absolute executable path.
  bool hasKnownCliExecutable(CliTool cli) {
    if (configuredExecutablePath(cli).trim().isNotEmpty) return true;
    if (discoveredExecutablePath(cli).trim().isNotEmpty) return true;
    return _looksLikeAbsolutePath(resolveExecutable(cli));
  }

  /// True when [toolId] has a configured or discovered executable path.
  bool hasKnownToolchainExecutable(String toolId, String fallback) {
    if (toolchainPath(toolId).trim().isNotEmpty) return true;
    if (discoveredToolchainPath(toolId).trim().isNotEmpty) return true;
    return _looksLikeAbsolutePath(
      resolveToolchainExecutable(toolId, fallback),
    );
  }

  static bool _looksLikeAbsolutePath(String value) {
    return value.contains('/') || value.contains(r'\');
  }

  static Map<CliTool, String> _normalizeLocatedExecutables(
    Map<CliTool, String> locatedExecutables,
  ) {
    final normalized = <CliTool, String>{};
    for (final entry in locatedExecutables.entries) {
      final value = entry.value.trim();
      if (value.isNotEmpty) normalized[entry.key] = value;
    }
    return normalized;
  }

  static Map<String, String> _normalizeLocatedToolchains(
    Map<String, String> locatedToolchains,
  ) {
    final normalized = <String, String>{};
    for (final entry in locatedToolchains.entries) {
      final value = entry.value.trim();
      if (value.isNotEmpty) normalized[entry.key] = value;
    }
    return normalized;
  }
}
