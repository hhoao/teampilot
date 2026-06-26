import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/connection_mode.dart';
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
  }) : preferences = preferences ?? SessionPreferences();

  final SessionPreferences preferences;
  final bool isLoading;

  SessionPreferencesState copyWith({
    SessionPreferences? preferences,
    bool? isLoading,
  }) {
    return SessionPreferencesState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [preferences, isLoading];
}

class SessionPreferencesCubit extends Cubit<SessionPreferencesState> {
  SessionPreferencesCubit({
    required SessionPreferencesRepository repository,
    Map<CliTool, String> locatedExecutables = const {},
    CliToolRegistry? cliToolRegistry,
  }) : _repository = repository,
       _locatedExecutables = _normalizeLocatedExecutables(locatedExecutables),
       _cliToolRegistry = cliToolRegistry ?? _defaultCliRegistry,
       super(SessionPreferencesState());

  static final _defaultCliRegistry = () {
    final r = CliToolRegistry.builtIn();
    return r;
  }();

  final SessionPreferencesRepository _repository;
  final Map<CliTool, String> _locatedExecutables;
  final CliToolRegistry _cliToolRegistry;

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
    final pathKey = _cliToolRegistry
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
  /// Checks the user-configured [toolchainPath] first, then falls back to
  /// [fallback] (typically the bare command name for PATH lookup).
  String resolveToolchainExecutable(String toolId, String fallback) {
    final configured = toolchainPath(toolId);
    if (configured.isNotEmpty) return configured;
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
    return _save(
      state.preferences.copyWith(terminalScrollbackLines: clamped),
    );
  }

  Future<void> setTerminalLinkClickOpensInApp(bool value) {
    return _save(
      state.preferences.copyWith(terminalLinkClickOpensInApp: value),
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
    final resolver =
        _cliToolRegistry.capability<ExecutableResolverCapability>(cli);
    return resolver?.defaultExecutableName ?? cli.value;
  }

  String _userExecutableFor(CliTool cli) {
    final pathKey = _cliToolRegistry
            .capability<ExecutableResolverCapability>(cli)
            ?.preferencesPathKey ??
        cli.value;
    return state.preferences.cliExecutablePathFor(pathKey);
  }

  static Map<CliTool, String> _normalizeLocatedExecutables(
    Map<CliTool, String> locatedExecutables,
  ) {
    final normalized = <CliTool, String>{};
    for (final entry in locatedExecutables.entries) {
      final value = entry.value.trim();
      if (value.isNotEmpty) normalized[entry.key] = value;
    }
    return Map.unmodifiable(normalized);
  }
}
