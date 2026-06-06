import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/extension_manifest.dart';
import '../models/extension_state.dart';
import '../repositories/extension_repository.dart';
import '../services/extension/extension_acquisition_engine.dart';
import '../services/extension/extension_detector.dart';

enum ExtensionLoadStatus { idle, loading, ready, error }

enum ExtensionStatusCode {
  notInstalled,
  ready,
  dependencyMissing,
  versionTooOld,
}

class ExtensionRow extends Equatable {
  const ExtensionRow({
    required this.id,
    required this.name,
    required this.description,
    required this.homepage,
    required this.globalEnabled,
    required this.installed,
    required this.status,
    this.version,
  });

  final String id;
  final String name;
  final String description;
  final String homepage;
  final bool globalEnabled;
  final bool installed;
  final ExtensionStatusCode status;
  final String? version;

  @override
  List<Object?> get props =>
      [id, name, description, homepage, globalEnabled, installed, status, version];
}

class ExtensionUiState extends Equatable {
  const ExtensionUiState({
    this.rows = const [],
    this.status = ExtensionLoadStatus.idle,
    this.errorMessage,
    this.busyIds = const {},
  });

  final List<ExtensionRow> rows;
  final ExtensionLoadStatus status;
  final String? errorMessage;
  final Set<String> busyIds;

  ExtensionUiState copyWith({
    List<ExtensionRow>? rows,
    ExtensionLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    Set<String>? busyIds,
  }) =>
      ExtensionUiState(
        rows: rows ?? this.rows,
        status: status ?? this.status,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        busyIds: busyIds ?? this.busyIds,
      );

  @override
  List<Object?> get props => [rows, status, errorMessage, busyIds];
}

class ExtensionCubit extends Cubit<ExtensionUiState> {
  ExtensionCubit(
    this._repository,
    this._engine, {
    ExtensionDetector? detector,
  })  : _detector = detector ?? ExtensionDetector(),
        super(const ExtensionUiState());

  final ExtensionRepository _repository;
  final ExtensionAcquisitionEngine _engine;
  final ExtensionDetector _detector;
  Future<void>? _loadFuture;

  /// Loads extension rows from the host. Skips work when already [ready] unless
  /// [force] is true (e.g. after SSH / storage backend changes).
  Future<void> load({bool force = false}) async {
    if (!force && state.status == ExtensionLoadStatus.ready) return;
    if (_loadFuture != null) return _loadFuture!;
    _loadFuture = _load(force: force);
    try {
      await _loadFuture;
    } finally {
      _loadFuture = null;
    }
  }

  Future<void> _load({required bool force}) async {
    if (!force && state.status == ExtensionLoadStatus.ready) return;
    if (state.rows.isEmpty) {
      emit(state.copyWith(status: ExtensionLoadStatus.loading, clearError: true));
    }
    try {
      final persisted = await _repository.load(forceReload: force);
      final rows = await Future.wait(
        _repository.manifests.map((m) => _buildRow(m, persisted)),
      );
      emit(state.copyWith(rows: rows, status: ExtensionLoadStatus.ready, clearError: true));
    } catch (e) {
      emit(state.copyWith(status: ExtensionLoadStatus.error, errorMessage: e.toString()));
    }
  }

  Future<ExtensionRow> _buildRow(
    ExtensionManifest manifest,
    ExtensionState persisted,
  ) async {
    final probe = await _detector.probe(manifest.detect);
    final globalEnabled = persisted.globalEnabled.contains(manifest.id);
    final status = !probe.found
        ? ExtensionStatusCode.notInstalled
        : probe.missingRequirements.isNotEmpty
            ? ExtensionStatusCode.dependencyMissing
            : !probe.satisfiesMinVersion
                ? ExtensionStatusCode.versionTooOld
                : ExtensionStatusCode.ready;
    return ExtensionRow(
      id: manifest.id,
      name: manifest.name,
      description: _description(manifest),
      homepage: manifest.homepage,
      globalEnabled: globalEnabled,
      installed: probe.found,
      status: status,
      version: probe.version,
    );
  }

  String _description(ExtensionManifest manifest) {
    final effect = manifest.effects.isEmpty ? '' : manifest.effects.first.kind;
    return effect;
  }

  Future<void> setGlobalEnabled(String id, bool enabled) async {
    await _withBusy(id, () async {
      await _repository.setGlobalEnabled(id, enabled);
      await _replaceRow(id);
    });
  }

  /// Current per-team override map (`{extensionId: bool}`) for [teamId].
  Future<Map<String, bool>> teamOverrides(String teamId) async {
    final state = await _repository.load();
    return Map<String, bool>.from(state.teamOverrides[teamId] ?? const {});
  }

  /// [value] null clears the override (the team falls back to global).
  Future<void> setTeamOverride(String teamId, String id, bool? value) async {
    await _repository.setTeamOverride(teamId, id, value);
  }

  Future<void> install(String id) async {
    await _withBusy(id, () async {
      final manifest = _repository.manifests.firstWhere((m) => m.id == id);
      final result = await _engine.install(manifest);
      if (result.success) {
        await _repository.recordInstalled(id, result.version ?? '');
      } else {
        emit(state.copyWith(errorMessage: result.message));
      }
      await _replaceRow(id);
    });
  }

  Future<void> uninstall(String id) async {
    await _withBusy(id, () async {
      final manifest = _repository.manifests.firstWhere((m) => m.id == id);
      final result = await _engine.uninstall(manifest);
      if (result.success) {
        await _repository.recordUninstalled(id);
      } else {
        emit(state.copyWith(errorMessage: result.message));
      }
      await _replaceRow(id);
    });
  }

  Future<void> _replaceRow(String id) async {
    final manifest = _repository.manifests.firstWhere((m) => m.id == id);
    final persisted = await _repository.load();
    final updated = await _buildRow(manifest, persisted);
    emit(state.copyWith(
      rows: [for (final r in state.rows) if (r.id == id) updated else r],
    ));
  }

  Future<void> _withBusy(String id, Future<void> Function() body) async {
    emit(state.copyWith(busyIds: {...state.busyIds, id}, clearError: true));
    try {
      await body();
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    } finally {
      emit(state.copyWith(busyIds: {...state.busyIds}..remove(id)));
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
