import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import '../models/plugin.dart';
import '../repositories/plugin_repository.dart';
import '../services/plugin_install_service.dart';
import '../services/plugin_repo_disk_cache_service.dart';
import '../services/plugin_repo_service.dart';
import '../utils/logger.dart';

enum PluginLoadStatus { idle, loading, ready, error }

class PluginState extends Equatable {
  const PluginState({
    this.installed = const [],
    this.marketplaces = const [],
    this.discoverable = const [],
    this.updates = const [],
    this.status = PluginLoadStatus.idle,
    this.errorMessage,
    this.busyIds = const {},
    this.discoveryLoading = false,
    this.updatesLoading = false,
    this.marketplaceSyncingKeys = const {},
  });

  final List<Plugin> installed;
  final List<PluginMarketplace> marketplaces;
  final List<DiscoverablePlugin> discoverable;
  final List<PluginUpdateInfo> updates;
  final PluginLoadStatus status;
  final String? errorMessage;
  final Set<String> busyIds;
  final bool discoveryLoading;
  final bool updatesLoading;
  final Set<String> marketplaceSyncingKeys;

  PluginState copyWith({
    List<Plugin>? installed,
    List<PluginMarketplace>? marketplaces,
    List<DiscoverablePlugin>? discoverable,
    List<PluginUpdateInfo>? updates,
    PluginLoadStatus? status,
    String? errorMessage,
    bool clearError = false,
    Set<String>? busyIds,
    bool? discoveryLoading,
    bool? updatesLoading,
    Set<String>? marketplaceSyncingKeys,
  }) => PluginState(
    installed: installed ?? this.installed,
    marketplaces: marketplaces ?? this.marketplaces,
    discoverable: discoverable ?? this.discoverable,
    updates: updates ?? this.updates,
    status: status ?? this.status,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    busyIds: busyIds ?? this.busyIds,
    discoveryLoading: discoveryLoading ?? this.discoveryLoading,
    updatesLoading: updatesLoading ?? this.updatesLoading,
    marketplaceSyncingKeys: marketplaceSyncingKeys ?? this.marketplaceSyncingKeys,
  );

  @override
  List<Object?> get props => [
    installed, marketplaces, discoverable, updates, status, errorMessage,
    busyIds, discoveryLoading, updatesLoading, marketplaceSyncingKeys,
  ];
}

class PluginCubit extends Cubit<PluginState> {
  PluginCubit({
    required this.repository,
    required this.installService,
    required this.repoService,
    PluginRepoDiskCacheService? diskCache,
  })  : _diskCache = diskCache ?? PluginRepoDiskCacheService(),
        super(const PluginState());

  /// Test-only constructor that skips service wiring and accepts a pre-built
  /// state. Do not use in production.
  @visibleForTesting
  PluginCubit.test(PluginState state)
      : repository = _dummyRepo,
        installService = _dummyInstallService,
        repoService = _dummyRepoService,
        _diskCache = PluginRepoDiskCacheService(),
        super(state);

  static final _dummyRepo = PluginRepository();
  static final _dummyInstallService = PluginInstallService();
  static final _dummyRepoService = PluginRepoService();

  final PluginRepository repository;
  final PluginInstallService installService;
  final PluginRepoService repoService;
  final PluginRepoDiskCacheService _diskCache;
  int _discoveryGeneration = 0;

  Future<void> load() async {
    emit(state.copyWith(status: PluginLoadStatus.loading, clearError: true));
    try {
      final results = await Future.wait([
        repository.loadAll(),
        repoService.loadMarketplaces(),
      ]);
      final installed = results[0] as List<Plugin>;
      final marketplaces = results[1] as List<PluginMarketplace>;
      emit(state.copyWith(
        installed: installed,
        marketplaces: marketplaces,
        status: PluginLoadStatus.ready,
      ));
      unawaited(refreshDiscoverable());
    } catch (e) {
      appLogger.e('[plugins] load failed: $e');
      emit(state.copyWith(status: PluginLoadStatus.error, errorMessage: '$e'));
    }
  }

  Future<void> refreshDiscoverable({bool force = false}) async {
    final enabled = state.marketplaces.where((m) => m.enabled).toList();
    if (enabled.isEmpty) {
      emit(state.copyWith(
        discoveryLoading: false,
        discoverable: const [],
        marketplaceSyncingKeys: const {},
      ));
      return;
    }
    await _syncMarketplacesInBackground(enabled, force: force, clearError: true);
  }

  Future<void> _syncMarketplacesInBackground(
    List<PluginMarketplace> marketplacesToSync, {
    bool force = false,
    bool clearError = false,
  }) async {
    if (marketplacesToSync.isEmpty) return;

    final generation = ++_discoveryGeneration;
    final enabled = state.marketplaces.where((m) => m.enabled).toList();
    var syncing = {
      ...state.marketplaceSyncingKeys,
      ...marketplacesToSync.map(PluginRepoDiskCacheService.repoKey),
    };
    emit(state.copyWith(
      discoveryLoading: true,
      discoverable: await _aggregateDiscoverableFromDisk(enabled),
      marketplaceSyncingKeys: syncing,
      clearError: clearError,
    ));

    final batchKeys = marketplacesToSync
        .map(PluginRepoDiskCacheService.repoKey)
        .toSet();
    final remaining = Set<String>.from(batchKeys);

    Future<void> onRepoSyncFinished(String key) async {
      if (generation != _discoveryGeneration) return;
      remaining.remove(key);
      final discoverable = await _aggregateDiscoverableFromDisk(
        state.marketplaces.where((m) => m.enabled).toList(),
      );
      if (generation != _discoveryGeneration) return;
      final marketplaceSyncingKeys = {
        ...state.marketplaceSyncingKeys.where((k) => !batchKeys.contains(k)),
        ...remaining,
      };
      emit(state.copyWith(
        discoverable: discoverable,
        discoveryLoading: marketplaceSyncingKeys.isNotEmpty,
        marketplaceSyncingKeys: marketplaceSyncingKeys,
      ));
    }

    await Future.wait(
      marketplacesToSync.map((m) async {
        final key = PluginRepoDiskCacheService.repoKey(m);
        try {
          await _diskCache.syncMarketplace(m);
        } catch (e) {
          appLogger.w('[plugins] sync ${m.fullName} failed: $e');
        } finally {
          await onRepoSyncFinished(key);
        }
      }),
    );

    if (generation != _discoveryGeneration) return;
    final marketplaceSyncingKeys =
        state.marketplaceSyncingKeys.where((k) => !batchKeys.contains(k)).toSet();
    emit(state.copyWith(
      discoveryLoading: false,
      marketplaceSyncingKeys: marketplaceSyncingKeys,
      discoverable: await _aggregateDiscoverableFromDisk(
        state.marketplaces.where((m) => m.enabled).toList(),
      ),
    ));
  }

  Future<List<DiscoverablePlugin>> _aggregateDiscoverableFromDisk(
    List<PluginMarketplace> enabled,
  ) async {
    final seen = <String>{};
    final out = <DiscoverablePlugin>[];
    for (final m in enabled) {
      try {
        for (final d in await _diskCache.discoverablePlugins(m)) {
          if (seen.add(d.key)) out.add(d);
        }
      } catch (e) {
        appLogger.w('[plugins] read cached discoverable ${m.fullName}: $e');
      }
    }
    return out;
  }

  Future<void> installFromDiscovery(DiscoverablePlugin d) async {
    final busy = {...state.busyIds, d.key};
    emit(state.copyWith(busyIds: busy, clearError: true));
    try {
      final marketDir = await _diskCache.syncMarketplace(PluginMarketplace(
        owner: d.marketplaceOwner,
        name: d.marketplaceName,
        branch: d.marketplaceBranch,
      ));
      final sourceDir = Directory('$marketDir/${d.source}');
      await installService.installFromDirectory(
        sourceDir,
        marketplace: PluginMarketplace(
          owner: d.marketplaceOwner,
          name: d.marketplaceName,
          branch: d.marketplaceBranch,
        ),
      );
      final installed = await repository.loadAll();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(d.key);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> installFromZip(File zip) async {
    emit(state.copyWith(clearError: true));
    try {
      await installService.installFromZip(zip);
      final installed = await repository.loadAll();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    }
  }

  Future<void> uninstall(Plugin plugin) async {
    final busy = {...state.busyIds, plugin.id};
    emit(state.copyWith(busyIds: busy, clearError: true));
    try {
      await installService.uninstall(plugin);
      final installed = await repository.loadAll();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(plugin.id);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> addMarketplace(PluginMarketplace m) async {
    await repoService.addMarketplace(m);
    final marketplaces = await repoService.loadMarketplaces();
    emit(state.copyWith(marketplaces: marketplaces));
  }

  Future<void> removeMarketplace(String owner, String name) async {
    await repoService.removeMarketplace(owner, name);
    final marketplaces = await repoService.loadMarketplaces();
    final discoverable = state.discoverable
        .where((d) => d.marketplaceOwner != owner || d.marketplaceName != name)
        .toList();
    emit(state.copyWith(marketplaces: marketplaces, discoverable: discoverable));
  }

  Future<void> toggleMarketplaceEnabled(PluginMarketplace m, bool enabled) async {
    await repoService.setEnabled(m.owner, m.name, enabled);
    final marketplaces = await repoService.loadMarketplaces();
    emit(state.copyWith(marketplaces: marketplaces));
  }

  Future<void> checkUpdates() async {
    emit(state.copyWith(updatesLoading: true));
    try {
      final updates = <PluginUpdateInfo>[];
      // Updates check requires network; placeholder for Phase 3.
      emit(state.copyWith(updates: updates, updatesLoading: false));
    } catch (e) {
      emit(state.copyWith(updatesLoading: false, errorMessage: '$e'));
    }
  }

  Future<void> updatePlugin(Plugin plugin) async {
    final busy = {...state.busyIds, plugin.id};
    emit(state.copyWith(busyIds: busy, clearError: true));
    try {
      // Update requires downloading new version from marketplace.
      // Placeholder for Phase 3.
      final installed = await repository.loadAll();
      emit(state.copyWith(installed: installed));
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(plugin.id);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> updateAll() async {
    for (final u in List<PluginUpdateInfo>.from(state.updates)) {
      final match = state.installed.where((p) => p.id == u.id).toList();
      if (match.isEmpty) continue;
      await updatePlugin(match.first);
    }
  }

  void clearError() => emit(state.copyWith(clearError: true));
}
