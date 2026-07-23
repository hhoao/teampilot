import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/resource_manager/process_metrics_service.dart';
import '../services/resource_manager/pty_process_registry.dart';
import '../services/resource_manager/resource_binding.dart';
import '../services/resource_manager/resource_memory_models.dart';
import '../services/resource_manager/resource_tree_merge.dart';

class ResourceManagerState extends Equatable {
  const ResourceManagerState({
    this.workspaceId,
    this.isOpen = false,
    this.bindings = const [],
    this.snapshot,
    this.tree,
    this.terminalCount = 0,
    this.error,
    this.expandedGroupKeys = const {},
  });

  final String? workspaceId;
  final bool isOpen;
  final List<ResourceBinding> bindings;
  final ResourceMemorySnapshot? snapshot;
  final ResourceTreeViewModel? tree;
  final int terminalCount;
  final String? error;
  final Set<String> expandedGroupKeys;

  ResourceManagerState copyWith({
    String? workspaceId,
    bool? isOpen,
    List<ResourceBinding>? bindings,
    ResourceMemorySnapshot? snapshot,
    ResourceTreeViewModel? tree,
    int? terminalCount,
    String? error,
    Set<String>? expandedGroupKeys,
    bool clearError = false,
    bool clearWorkspaceId = false,
  }) {
    return ResourceManagerState(
      workspaceId: clearWorkspaceId ? null : (workspaceId ?? this.workspaceId),
      isOpen: isOpen ?? this.isOpen,
      bindings: bindings ?? this.bindings,
      snapshot: snapshot ?? this.snapshot,
      tree: tree ?? this.tree,
      terminalCount: terminalCount ?? this.terminalCount,
      error: clearError ? null : (error ?? this.error),
      expandedGroupKeys: expandedGroupKeys ?? this.expandedGroupKeys,
    );
  }

  @override
  List<Object?> get props => [
        workspaceId,
        isOpen,
        bindings,
        snapshot,
        tree,
        terminalCount,
        error,
        expandedGroupKeys,
      ];
}

/// Owns Resource Manager panel open state, open-only metrics polling, registry
/// sync from live PTY pids, and kill/refresh actions.
class ResourceManagerCubit extends Cubit<ResourceManagerState> {
  ResourceManagerCubit({
    required ProcessMetricsService metricsService,
    required PtyProcessRegistry registry,
    required List<ResourceBinding> Function() bindingsSource,
    required Future<void> Function(String bindingKey) killBinding,
    Duration pollInterval = const Duration(seconds: 2),
  })  : _metricsService = metricsService,
        _registry = registry,
        _bindingsSource = bindingsSource,
        _killBinding = killBinding,
        _pollInterval = pollInterval,
        super(const ResourceManagerState());

  final ProcessMetricsService _metricsService;
  final PtyProcessRegistry _registry;
  final List<ResourceBinding> Function() _bindingsSource;
  final Future<void> Function(String bindingKey) _killBinding;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _collectInFlight = false;

  void setWorkspace(String? workspaceId) {
    if (workspaceId == state.workspaceId) return;
    _stopPolling();
    final bindings = _readBindings();
    final tree = mergeResourceTree(
      bindings: bindings,
      snapshot: state.snapshot,
    );
    emit(
      state.copyWith(
        workspaceId: workspaceId,
        clearWorkspaceId: workspaceId == null,
        isOpen: false,
        bindings: bindings,
        tree: tree,
        terminalCount: tree.terminalCount,
        clearError: true,
      ),
    );
  }

  Future<void> openPanel() async {
    if (state.isOpen) {
      await _tick();
      return;
    }
    emit(state.copyWith(isOpen: true, clearError: true));
    _startPolling();
    await _tick();
  }

  void closePanel() {
    if (!state.isOpen && _pollTimer == null) return;
    _stopPolling();
    // Keep snapshot (last good) for the closed pill memory badge.
    emit(state.copyWith(isOpen: false));
  }

  Future<void> togglePanel() async {
    if (state.isOpen) {
      closePanel();
    } else {
      await openPanel();
    }
  }

  Future<void> refresh() async {
    if (!state.isOpen) return;
    await _tick();
  }

  Future<void> killLeaf(String bindingKey) async {
    try {
      await _killBinding(bindingKey);
      if (!isClosed) {
        emit(state.copyWith(clearError: true));
      }
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(error: e.toString()));
      }
    }
  }

  Future<void> killAll() async {
    final keys = state.tree?.groups
            .expand((g) => g.leaves)
            .map((l) => l.key)
            .toList() ??
        state.bindings.map((b) => b.key).toList();
    for (final key in keys) {
      await killLeaf(key);
    }
  }

  void onRouteActiveChanged(bool active) {
    if (!active) {
      closePanel();
    }
  }

  /// Clear-and-replace [PtyProcessRegistry] from current bindings' non-null
  /// [ResourceBinding.livePid] values only.
  void syncRegistryFromBindings() {
    final bindings = _readBindings();
    _replaceRegistry(bindings);
    if (isClosed) return;
    if (_bindingsVisuallyEqual(state.bindings, bindings) &&
        state.terminalCount == bindings.length) {
      // Same inventory: skip emit so closed pill / open panel do not rebuild.
      return;
    }
    final tree = mergeResourceTree(
      bindings: bindings,
      snapshot: state.snapshot,
    );
    emit(
      state.copyWith(
        bindings: bindings,
        tree: tree,
        terminalCount: tree.terminalCount,
      ),
    );
  }

  static bool _bindingsVisuallyEqual(
    List<ResourceBinding> a,
    List<ResourceBinding> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.key != y.key ||
          x.kind != y.kind ||
          x.groupKey != y.groupKey ||
          x.groupLabel != y.groupLabel ||
          x.title != y.title ||
          x.connected != y.connected ||
          x.livePid != y.livePid ||
          x.sessionId != y.sessionId ||
          x.memberId != y.memberId ||
          x.workspaceId != y.workspaceId ||
          x.shellEntryId != y.shellEntryId) {
        return false;
      }
    }
    return true;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_tick());
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _tick() async {
    if (isClosed || !state.isOpen || _collectInFlight) return;
    _collectInFlight = true;
    try {
      final bindings = _readBindings();
      _replaceRegistry(bindings);

      final bindingKeyToGroupKey = <String, String>{
        for (final b in bindings) b.key: b.groupKey,
      };

      try {
        final snapshot = await _metricsService.collect(
          registeredPids: _registry.asMap,
          bindingKeyToGroupKey: bindingKeyToGroupKey,
        );
        if (isClosed || !state.isOpen) return;
        final tree = mergeResourceTree(
          bindings: bindings,
          snapshot: snapshot,
        );
        emit(
          state.copyWith(
            bindings: bindings,
            snapshot: snapshot,
            tree: tree,
            terminalCount: tree.terminalCount,
            clearError: true,
          ),
        );
      } catch (e) {
        if (isClosed) return;
        final tree = mergeResourceTree(
          bindings: bindings,
          snapshot: state.snapshot,
        );
        emit(
          state.copyWith(
            bindings: bindings,
            tree: tree,
            terminalCount: tree.terminalCount,
            error: e.toString(),
          ),
        );
      }
    } finally {
      _collectInFlight = false;
    }
  }

  List<ResourceBinding> _readBindings() =>
      List<ResourceBinding>.unmodifiable(_bindingsSource());

  void _replaceRegistry(List<ResourceBinding> bindings) {
    final desired = <String, int>{
      for (final b in bindings)
        if (b.livePid != null) b.key: b.livePid!,
    };
    for (final key in _registry.asMap.keys.toList()) {
      if (!desired.containsKey(key)) {
        _registry.unregister(key);
      }
    }
    for (final entry in desired.entries) {
      _registry.register(bindingKey: entry.key, pid: entry.value);
    }
  }

  @override
  Future<void> close() {
    _stopPolling();
    return super.close();
  }
}
