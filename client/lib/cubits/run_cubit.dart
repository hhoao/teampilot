import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/run/launch_configuration.dart';
import '../models/run/launch_type_contribution.dart';
import '../models/run/run_session.dart';
import '../models/run/run_ui_intent.dart';
import '../models/workspace_folder.dart';
import '../services/run/launch_adapter_protocol.dart';
import '../services/run/launch_config_store.dart';
import '../services/run/launch_type_normalize.dart';
import '../services/run/run_platform.dart';
import '../services/run/shell_script_launch_schema.dart';
import '../services/run/shell_script_migrator.dart';

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
    for (final recommendation in recommendations) {
      if (recommendation.selectionKey == key) return recommendation;
    }
    return null;
  }

  OwnedLaunchCompound? get selectedCompound {
    final key = selectedKey;
    if (key == null) return null;
    for (final compound in compounds) {
      if (compound.selectionKey == key) return compound;
    }
    return null;
  }

  bool isRecommendation(OwnedLaunchConfiguration owned) {
    for (final recommendation in recommendations) {
      if (recommendation.selectionKey == owned.selectionKey) return true;
    }
    return false;
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
class RunCubit extends Cubit<RunState> {
  RunCubit({
    required RunPlatformApi platform,
    required List<WorkspaceFolder> folders,
  }) : _platform = platform,
       _folders = List<WorkspaceFolder>.unmodifiable(folders),
       super(const RunState());

  final RunPlatformApi _platform;
  final List<WorkspaceFolder> _folders;
  final StreamController<RunUiIntent> _uiIntentController =
      StreamController<RunUiIntent>.broadcast();

  RunPlatformApi get platform => _platform;
  List<WorkspaceFolder> get folders => _folders;

  /// Dock activation / focus requests from Shell Script launches.
  Stream<RunUiIntent> get uiIntents => _uiIntentController.stream;

  /// Sink used by [RunShellScriptLauncher] via the platform factory.
  void publishUiIntent(RunUiIntent intent) {
    if (!_uiIntentController.isClosed) {
      _uiIntentController.add(intent);
    }
  }

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

    _ensureSubscriptions();
    await refreshDiscover();
  }

  void _ensureSubscriptions() {
    _sessionsSub ??= _platform.sessionsStream.listen((sessions) {
      if (!isClosed) emit(state.copyWith(sessions: sessions));
    });
    _actionsSub ??= _platform.actionsStream.listen((actions) {
      if (!isClosed) emit(state.copyWith(actions: actions));
    });
  }

  Future<void> select(String selectionKey) async {
    final compound = _findCompound(selectionKey);
    if (compound != null) {
      await _optionsSub?.cancel();
      _optionsSub = null;
      emit(
        state.copyWith(
          selectedKey: selectionKey,
          options: const [],
          optionValues: const {},
          clearError: true,
        ),
      );
      return;
    }

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

    if (isBuiltInShellType(owned.configuration.type)) {
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

  void reportError(String message) {
    emit(state.copyWith(errorMessage: message));
  }

  Future<void> runSelected() async {
    final compound = state.selectedCompound;
    if (compound != null) {
      await runCompound(compound);
      return;
    }

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

  Future<void> runCompound(OwnedLaunchCompound owned) async {
    final documentConfigs = state.configurations
        .where((config) => config.owner == owned.owner)
        .toList();

    try {
      final sessionIds = await _platform.startCompound(
        owned: owned,
        documentConfigs: documentConfigs,
      );
      final errors = _platform.sessionManager.lastCompoundErrors;
      emit(
        state.copyWith(
          sessions: _platform.sessions,
          errorMessage: errors.isEmpty ? null : errors.join('; '),
          clearError: errors.isEmpty,
        ),
      );
      if (sessionIds.isEmpty && errors.isEmpty) {
        emit(
          state.copyWith(
            errorMessage: 'compound produced no sessions',
          ),
        );
      }
    } catch (error) {
      emit(state.copyWith(errorMessage: error.toString()));
    }
  }

  Future<void> stopSession(String sessionId) async {
    await _platform.stop(sessionId);
    emit(state.copyWith(sessions: _platform.sessions, clearError: true));
  }

  /// Stops (if running) and removes a session from the bottom Run panel.
  Future<void> dismissSession(String sessionId) async {
    await _platform.sessionManager.dismiss(sessionId);
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

  /// Refreshes glob-based discover recommendations for workspace folders.
  Future<void> refreshDiscover() async {
    try {
      final recommendations = await _platform.discoverRecommendations(
        _folders,
        existing: state.configurations,
      );
      if (!isClosed) {
        emit(state.copyWith(recommendations: recommendations, clearError: true));
      }
    } catch (error) {
      if (!isClosed) {
        emit(state.copyWith(errorMessage: error.toString()));
      }
    }
  }

  /// Persists a discover recommendation into the owning folder's `launch.json`.
  ///
  /// The Run toolbar / dropdown opens the Edit Configurations dialog for
  /// recommendations instead of calling this directly. Keep this method for
  /// programmatic save of recommendation drafts (same persist path as editor
  /// Save / [saveConfiguration]).
  Future<void> acceptRecommendation(OwnedLaunchConfiguration recommendation) async {
    final errors = _platform.validateConfiguration(recommendation);
    if (errors.isNotEmpty) {
      emit(state.copyWith(errorMessage: errors.join('; ')));
      return;
    }

    try {
      await _platform.persistConfiguration(
        folder: recommendation.owner,
        configuration: recommendation.configuration,
      );
      final acceptedKey = recommendation.selectionKey;
      await load();
      if (!isClosed) {
        final persisted = state.configurations
            .where((item) => item.selectionKey == acceptedKey)
            .firstOrNull;
        if (persisted != null) {
          emit(
            state.copyWith(
              selectedKey: persisted.selectionKey,
              options: const [],
              optionValues: const {},
              clearError: true,
            ),
          );
        }
      }
    } catch (error) {
      if (!isClosed) {
        emit(state.copyWith(errorMessage: error.toString()));
      }
    }
  }

  /// Persists [owned], reloads, and selects the saved configuration.
  ///
  /// Id may be assigned on write via [LaunchConfigDocument.normalized]; after
  /// reload, selection matches by id when present, else name/type/owner.
  Future<void> saveConfiguration(OwnedLaunchConfiguration owned) async {
    final errors = _platform.validateConfiguration(owned);
    if (errors.isNotEmpty) {
      emit(state.copyWith(errorMessage: errors.join('; ')));
      return;
    }

    try {
      await _platform.persistConfiguration(
        folder: owned.owner,
        configuration: owned.configuration,
      );
      await load();
      if (isClosed) return;
      final selectionKey = _selectionKeyAfterPersist(owned);
      if (selectionKey != null) {
        await select(selectionKey);
      }
    } catch (error) {
      if (!isClosed) {
        emit(state.copyWith(errorMessage: error.toString()));
      }
    }
  }

  /// Removes [owned] from its folder's `launch.json` (no UI confirm).
  ///
  /// Stops a running session for this config first, then deletes and reloads.
  /// Clears selection when the deleted config was selected.
  Future<void> deleteConfiguration(OwnedLaunchConfiguration owned) async {
    final deletedKey = owned.selectionKey;
    final running = runningSessionFor(deletedKey);
    if (running != null) {
      await stopSession(running.id);
    }

    try {
      await _platform.deleteConfiguration(
        folder: owned.owner,
        id: owned.configId,
      );
      final wasSelected = state.selectedKey == deletedKey;
      await load();
      if (isClosed) return;
      if (wasSelected) {
        await _optionsSub?.cancel();
        _optionsSub = null;
        emit(
          state.copyWith(
            clearSelectedKey: true,
            options: const [],
            optionValues: const {},
            clearError: true,
          ),
        );
      }
    } catch (error) {
      if (!isClosed) {
        emit(state.copyWith(errorMessage: error.toString()));
      }
    }
  }

  /// In-memory draft; id is assigned on [saveConfiguration] via document normalize.
  OwnedLaunchConfiguration createConfiguration({
    required WorkspaceFolder folder,
    required String type,
  }) {
    final normalized = normalizeLaunchType(type);
    if (isBuiltInShellType(normalized)) {
      return OwnedLaunchConfiguration(
        owner: folder,
        configuration: LaunchConfiguration.fromJson(
          ShellScriptLaunchSchema.withDefaults({
            'type': ShellScriptLaunchSchema.typeName,
            'id': '',
            'name': '',
          }),
        ),
      );
    }
    return OwnedLaunchConfiguration(
      owner: folder,
      configuration: LaunchConfiguration(
        id: '',
        name: '',
        type: normalized,
      ),
    );
  }

  /// Schema for the Edit Configurations form; null when [type] is unknown.
  Map<String, Object?>? schemaForType(String type) =>
      _platform.configurationSchema(type);

  /// Registered launch types for the Add-configuration type picker.
  List<LaunchTypeContribution> get launchTypes => _platform.launchTypes;

  /// Capability kinds for [type] (defaults to `run` when unknown).
  List<String> kindsForType(String type) => _platform.kindsFor(type);

  /// Whether the selected configuration currently fails schema validation
  /// (including applied option values).
  bool get selectedHasSchemaErrors {
    final owned = state.selectedConfiguration;
    if (owned == null) return false;
    return _platform.validateConfiguration(_applyOptionValues(owned)).isNotEmpty;
  }

  String? _selectionKeyAfterPersist(OwnedLaunchConfiguration owned) {
    final id = owned.configuration.id.trim();
    if (id.isNotEmpty) {
      final byId = state.configurations
          .where(
            (item) =>
                item.owner == owned.owner && item.configuration.id == id,
          )
          .firstOrNull;
      if (byId != null) return byId.selectionKey;
    }

    final byIdentity = state.configurations
        .where(
          (item) =>
              item.owner == owned.owner &&
              _launchTypesMatch(
                item.configuration.type,
                owned.configuration.type,
              ) &&
              item.configuration.name == owned.configuration.name,
        )
        .firstOrNull;
    return byIdentity?.selectionKey;
  }

  /// `process` migrates to `shellScript` on read; treat them as the same identity.
  static bool _launchTypesMatch(String loaded, String saved) {
    if (loaded == saved) return true;
    const aliases = {
      ShellScriptLaunchSchema.processAlias,
      ShellScriptLaunchSchema.typeName,
    };
    return aliases.contains(loaded) && aliases.contains(saved);
  }

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
        ShellScriptMigrator.maybeMigrate(
          Map<String, Object?>.from(response.configuration!),
        ),
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

  bool isConfigurationAvailable(OwnedLaunchConfiguration owned) =>
      _platform.isTypeAvailable(
        owned.configuration.type,
        targetId: owned.owner.targetId,
      );

  String? unavailableReason(OwnedLaunchConfiguration owned) =>
      _platform.unavailableReason(
        owned.configuration.type,
        targetId: owned.owner.targetId,
      );

  bool isTypeAvailableForTarget(String type, {required String targetId}) =>
      _platform.isTypeAvailable(type, targetId: targetId);

  String? unavailableReasonForType(String type, {required String targetId}) =>
      _platform.unavailableReason(type, targetId: targetId);

  bool isActionAvailable(LaunchAdapterConfigurationEntry action) {
    final targetId =
        state.selectedConfiguration?.owner.targetId ??
        _folders.firstOrNull?.targetId ??
        WorkspaceFolder.localTargetId;
    return _platform.isTypeAvailable(action.type, targetId: targetId);
  }

  String? actionUnavailableReason(LaunchAdapterConfigurationEntry action) {
    final targetId =
        state.selectedConfiguration?.owner.targetId ??
        _folders.firstOrNull?.targetId ??
        WorkspaceFolder.localTargetId;
    return _platform.unavailableReason(action.type, targetId: targetId);
  }

  bool hasRunningCompound(String compoundId) =>
      runningSessionIdsForCompound(compoundId).isNotEmpty;

  List<String> runningSessionIdsForCompound(String compoundId) {
    return [
      for (final session in state.sessions)
        if (session.compoundId == compoundId &&
            (session.status == RunSessionStatus.running ||
                session.status == RunSessionStatus.starting))
          session.id,
    ];
  }

  bool hasRunning(String selectionKey) =>
      _platform.sessionManager.hasRunning(selectionKey);

  RunSession? runningSessionFor(String selectionKey) {
    for (final session in state.sessions) {
      if (session.selectionKey == selectionKey &&
          (session.status == RunSessionStatus.running ||
              session.status == RunSessionStatus.starting)) {
        return session;
      }
    }
    return null;
  }

  OwnedLaunchConfiguration? _findConfiguration(String selectionKey) {
    for (final config in state.configurations) {
      if (config.selectionKey == selectionKey) return config;
    }
    for (final recommendation in state.recommendations) {
      if (recommendation.selectionKey == selectionKey) return recommendation;
    }
    return null;
  }

  OwnedLaunchCompound? _findCompound(String selectionKey) {
    for (final compound in state.compounds) {
      if (compound.selectionKey == selectionKey) return compound;
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
    final sessions = _sessionsSub;
    final actions = _actionsSub;
    final options = _optionsSub;
    _sessionsSub = null;
    _actionsSub = null;
    _optionsSub = null;
    // Broadcast cancel can stall when a listener emit is notifying watched
    // widgets; drop refs and cancel without blocking dispose.
    sessions?.cancel();
    actions?.cancel();
    await options?.cancel();
    await _uiIntentController.close();
    return super.close();
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}

extension on List<WorkspaceFolder> {
  WorkspaceFolder? get firstOrNull => isEmpty ? null : first;
}
