import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/connection_mode.dart';
import '../models/session_preferences.dart';
import '../services/cli/cli_tool_locator.dart';
import '../models/team_config.dart';
import '../models/windows_storage_backend.dart';
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
    String? locatedExecutable,
    Map<TeamCli, String> locatedExecutables = const {},
  }) : _repository = repository,
       _locatedExecutables = _normalizeLocatedExecutables(
         locatedExecutable: locatedExecutable,
         locatedExecutables: locatedExecutables,
       ),
       super(SessionPreferencesState());

  final SessionPreferencesRepository _repository;
  final Map<TeamCli, String> _locatedExecutables;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final prefs = await _repository.load();
    emit(state.copyWith(preferences: prefs, isLoading: false));
  }

  Future<void> _save(SessionPreferences preferences) async {
    emit(state.copyWith(preferences: preferences));
    await _repository.save(preferences);
  }

  Future<void> setConnectionMode(ConnectionMode mode) {
    return _save(state.preferences.copyWith(connectionMode: mode));
  }

  bool get isSshMode => state.preferences.connectionMode == ConnectionMode.ssh;

  Future<void> setCliExecutablePath(String value) {
    return _save(state.preferences.copyWith(cliExecutablePath: value.trim()));
  }

  Future<void> setCliExecutablePathFor(TeamCli cli, String value) {
    if (cli == TeamCli.flashskyai) {
      return setCliExecutablePath(value);
    }
    final next = Map<String, String>.of(state.preferences.cliExecutablePaths);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      next.remove(cli.value);
    } else {
      next[cli.value] = trimmed;
    }
    return _save(state.preferences.copyWith(cliExecutablePaths: next));
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

  Future<void> setWindowsStorageBackend(WindowsStorageBackend backend) {
    return _save(state.preferences.copyWith(windowsStorageBackend: backend));
  }

  /// Returns the actual executable string to invoke for [cli]:
  ///   1. user-configured path (if non-empty after trim)
  ///   2. path discovered at startup (if non-null and non-empty)
  ///   3. the CLI's command name (OS resolves via PATH)
  String resolveExecutable([TeamCli cli = TeamCli.flashskyai]) {
    final user = _userExecutableFor(cli);
    if (user.isNotEmpty) {
      return CliToolLocator.resolveSpawnExecutable(user);
    }
    final located = _locatedExecutables[cli];
    if (located != null && located.isNotEmpty) {
      return CliToolLocator.resolveSpawnExecutable(located);
    }
    return cli.value;
  }

  String _userExecutableFor(TeamCli cli) {
    if (cli == TeamCli.flashskyai) {
      return state.preferences.cliExecutablePath.trim();
    }
    return state.preferences.cliExecutablePaths[cli.value]?.trim() ?? '';
  }

  static Map<TeamCli, String> _normalizeLocatedExecutables({
    required String? locatedExecutable,
    required Map<TeamCli, String> locatedExecutables,
  }) {
    final normalized = <TeamCli, String>{};
    for (final entry in locatedExecutables.entries) {
      final value = entry.value.trim();
      if (value.isNotEmpty) normalized[entry.key] = value;
    }
    final legacy = locatedExecutable?.trim();
    if (legacy != null && legacy.isNotEmpty) {
      normalized.putIfAbsent(TeamCli.flashskyai, () => legacy);
    }
    return Map.unmodifiable(normalized);
  }
}
