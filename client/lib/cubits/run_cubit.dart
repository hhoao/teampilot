import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/run/launch_configuration.dart';
import '../models/run/run_session.dart';
import '../models/workspace_folder.dart';
import '../services/run/launch_adapter_protocol.dart';
import '../services/run/launch_config_store.dart';
import '../services/run/process_launch_schema.dart';
import '../services/run/run_platform.dart';

/// UI state for the per-workspace Run platform.
class RunState extends Equatable {
  const RunState({
    this.configurations = const [],
    this.compounds = const [],
    this.actions = const [],
    this.selectedKey,
    this.options = const [],
    this.optionValues = const {},
    this.sessions = const [],
    this.recommendations = const [],
    this.errorMessage,
  });

  final List<OwnedLaunchConfiguration> configurations;
  final List<OwnedLaunchCompound> compounds;
  final List<LaunchAdapterConfigurationEntry> actions;
  final String? selectedKey;
  final List<LaunchOption> options;
  final Map<String, Object?> optionValues;
  final List<RunSession> sessions;
  final List<OwnedLaunchConfiguration> recommendations;
  final String? errorMessage;

  OwnedLaunchConfiguration? get selectedConfiguration {
    final key = selectedKey;
    if (key == null) return null;
    for (final config in configurations) {
      if (config.selectionKey == key) return config;
    }
    return null;
  }

  RunState copyWith({
    List<OwnedLaunchConfiguration>? configurations,
    List<OwnedLaunchCompound>? compounds,
    List<LaunchAdapterConfigurationEntry>? actions,
    String? selectedKey,
    bool clearSelectedKey = false,
    List<LaunchOption>? options,
    Map<String, Object?>? optionValues,
    List<RunSession>? sessions,
    List<OwnedLaunchConfiguration>? recommendations,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RunState(
      configurations: configurations ?? this.configurations,
      compounds: compounds ?? this.compounds,
      actions: actions ?? this.actions,
      selectedKey: clearSelectedKey ? null : (selectedKey ?? this.selectedKey),
      options: options ?? this.options,
      optionValues: optionValues ?? this.optionValues,
      sessions: sessions ?? this.sessions,
      recommendations: recommendations ?? this.recommendations,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    configurations,
    compounds,
    actions,
    selectedKey,
    options,
    optionValues,
    sessions,
    recommendations,
    errorMessage,
  ];
}

/// Per-workspace cubit owning Run selection, options, and sessions.
///
/// TODO(Task 8): mount via BlocProvider at workspace scope (workspace_page /
/// IDE shell) — leave app_shell alone until the toolbar mount point is clear.
class RunCubit extends Cubit<RunState> {
  RunCubit({
    required RunPlatformApi platform,
    required List<WorkspaceFolder> folders,
  }) : _platform = platform,
       _folders = List<WorkspaceFolder>.unmodifiable(folders),
       super(const RunState());

  final RunPlatformApi _platform;
  final List<WorkspaceFolder> _folders;

  StreamSubscription<List<RunSession>>? _sessionsSub;
  StreamSubscription<List<LaunchAdapterConfigurationEntry>>? _actionsSub;
  StreamSubscription<List<LaunchOption>>? _optionsSub;

  Future<void> load() async {
    final configurations = await _platform.listConfigurations(_folders);
    final compounds = await _platform.listCompounds(_folders);
    emit(
      state.copyWith(
        configurations: configurations,
        compounds: compounds,
        sessions: _platform.sessions,
        clearError: true,
      ),
    );

    await _sessionsSub?.cancel();
    _sessionsSub = _platform.sessionsStream.listen((sessions) {
      if (!isClosed) emit(state.copyWith(sessions: sessions));
    });

    await _actionsSub?.cancel();
    _actionsSub = _platform.actionsStream.listen((actions) {
      if (!isClosed) emit(state.copyWith(actions: actions));
    });
  }

  Future<void> select(String selectionKey) async {
    final owned = _findConfiguration(selectionKey);
    await _optionsSub?.cancel();
    _optionsSub = null;

    if (owned == null) {
      emit(
        state.copyWith(
          clearSelectedKey: true,
          options: const [],
          optionValues: const {},
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        selectedKey: selectionKey,
        options: const [],
        optionValues: const {},
        clearError: true,
      ),
    );

    if (owned.configuration.type == ProcessLaunchSchema.typeName) {
      return;
    }

    final options = await _platform.provideOptions(owned);
    final values = <String, Object?>{
      for (final option in options)
        if (option.value != null) option.id: option.value,
    };
    if (!isClosed) {
      emit(state.copyWith(options: options, optionValues: values));
    }

    _optionsSub = _platform.optionsChangedFor(owned).listen((next) {
      if (isClosed) return;
      final merged = Map<String, Object?>.from(state.optionValues);
      for (final option in next) {
        if (option.value != null) {
          merged[option.id] = option.value;
        }
      }
      emit(state.copyWith(options: next, optionValues: merged));
    });
  }

  void setOption(String id, Object? value) {
    final next = Map<String, Object?>.from(state.optionValues)..[id] = value;
    emit(state.copyWith(optionValues: next, clearError: true));
  }

  Future<void> runSelected() async {
    final owned = state.selectedConfiguration;
    if (owned == null) {
      emit(state.copyWith(errorMessage: 'no configuration selected'));
      return;
    }

    final withOptions = _applyOptionValues(owned);
    final errors = _platform.validateConfiguration(withOptions);
    if (errors.isNotEmpty) {
      emit(state.copyWith(errorMessage: errors.join('; ')));
      return;
    }

    try {
      await _platform.start(withOptions);
      emit(
        state.copyWith(sessions: _platform.sessions, clearError: true),
      );
    } catch (error) {
      emit(state.copyWith(errorMessage: error.toString()));
    }
  }

  Future<void> stopSession(String sessionId) async {
    await _platform.stop(sessionId);
    emit(state.copyWith(sessions: _platform.sessions, clearError: true));
  }

  Future<void> restartSession(String sessionId) async {
    try {
      await _platform.restart(sessionId);
      emit(state.copyWith(sessions: _platform.sessions, clearError: true));
    } catch (error) {
      emit(state.copyWith(errorMessage: error.toString()));
    }
  }

  Future<void> stopCompound(List<String> sessionIds) async {
    await _platform.stopCompound(sessionIds);
    emit(state.copyWith(sessions: _platform.sessions, clearError: true));
  }

  /// Discover refresh — stub until Task 11.
  Future<void> refreshDiscover() async {}

  /// Accept a discover recommendation — stub until Task 11.
  Future<void> acceptRecommendation(OwnedLaunchConfiguration recommendation) async {}

  Future<void> configureAction({
    required String actionId,
    required String type,
    required Map<String, Object?> result,
    WorkspaceFolder? folder,
  }) async {
    final owner = folder ?? _folders.firstOrNull;
    if (owner == null) {
      emit(state.copyWith(errorMessage: 'no workspace folder'));
      return;
    }

    try {
      final response = await _platform.configureAction(
        actionId: actionId,
        workspaceFolder: owner.path,
        result: result,
        type: type,
        targetId: owner.targetId,
      );
      if (response.cancelled || response.configuration == null) return;

      final configuration = LaunchConfiguration.fromJson(
        response.configuration!,
      );
      if (response.persist) {
        final errors = _platform.validateConfiguration(
          OwnedLaunchConfiguration(owner: owner, configuration: configuration),
        );
        if (errors.isNotEmpty) {
          emit(state.copyWith(errorMessage: errors.join('; ')));
          return;
        }
        await _platform.persistConfiguration(
          folder: owner,
          configuration: configuration,
        );
        await load();
      }
    } catch (error) {
      emit(state.copyWith(errorMessage: error.toString()));
    }
  }

  /// Returns the path of the selected config's owning `launch.json`, or the
  /// first folder's path when nothing is selected (Task 8 may prompt).
  Future<String?> openLaunchJson({WorkspaceFolder? folder}) async {
    final owner =
        folder ?? state.selectedConfiguration?.owner ?? _folders.firstOrNull;
    if (owner == null) return null;
    return _platform.launchJsonPath(owner);
  }

  OwnedLaunchConfiguration? _findConfiguration(String selectionKey) {
    for (final config in state.configurations) {
      if (config.selectionKey == selectionKey) return config;
    }
    return null;
  }

  OwnedLaunchConfiguration _applyOptionValues(OwnedLaunchConfiguration owned) {
    if (state.optionValues.isEmpty) return owned;
    final extras = Map<String, Object?>.from(owned.configuration.extras);
    for (final entry in state.optionValues.entries) {
      extras[entry.key] = entry.value;
    }
    return OwnedLaunchConfiguration(
      owner: owned.owner,
      configuration: owned.configuration.copyWith(extras: extras),
    );
  }

  @override
  Future<void> close() async {
    await _sessionsSub?.cancel();
    await _actionsSub?.cancel();
    await _optionsSub?.cancel();
    return super.close();
  }
}

extension on List<WorkspaceFolder> {
  WorkspaceFolder? get firstOrNull => isEmpty ? null : first;
}
