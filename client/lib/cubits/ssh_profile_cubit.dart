import 'dart:async';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../models/ssh_profile.dart';
import '../models/team_config.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';
import '../services/cli/remote_cli_path_cache.dart';
import '../services/storage/home_ssh_profile_impact.dart';

class SshProfileState extends Equatable {
  const SshProfileState({
    this.profiles = const [],
    this.selectedProfileId = '',
    this.isLoading = false,
  });

  final List<SshProfile> profiles;
  final String selectedProfileId;
  final bool isLoading;

  SshProfile? get selectedProfile {
    try {
      return profiles.firstWhere((p) => p.id == selectedProfileId);
    } on StateError {
      return profiles.isNotEmpty ? profiles.first : null;
    }
  }

  bool get hasProfiles => profiles.isNotEmpty;

  SshProfileState copyWith({
    List<SshProfile>? profiles,
    String? selectedProfileId,
    bool? isLoading,
  }) {
    return SshProfileState(
      profiles: profiles ?? this.profiles,
      selectedProfileId: selectedProfileId ?? this.selectedProfileId,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [profiles, selectedProfileId, isLoading];
}

typedef RemoteCliPathsLocator =
    Future<Map<CliTool, String>> Function(SshProfile profile);
typedef RemoteCliPathHandler = Future<void> Function(CliTool cli, String path);

class SshProfileCubit extends Cubit<SshProfileState> {
  SshProfileCubit({
    required SshProfileRepository profileRepository,
    required SshCredentialStore credentialStore,
    RemoteCliPathsLocator? locateRemoteCliPaths,
    RemoteCliPathHandler? onRemoteCliLocated,
    void Function(String profileId)? invalidateProfileConnection,
    bool Function()? enableRemoteCliDiscovery,
    RemoteCliPathCache? remoteCliPathCache,
  }) : _profileRepository = profileRepository,
       _credentialStore = credentialStore,
       _locateRemoteCliPaths = locateRemoteCliPaths,
       _onRemoteCliLocated = onRemoteCliLocated,
       _invalidateProfileConnection = invalidateProfileConnection,
       _enableRemoteCliDiscovery = enableRemoteCliDiscovery,
       _remoteCliPathCache = remoteCliPathCache,
       super(const SshProfileState());

  final SshProfileRepository _profileRepository;
  final SshCredentialStore _credentialStore;
  final RemoteCliPathsLocator? _locateRemoteCliPaths;
  final RemoteCliPathHandler? _onRemoteCliLocated;
  final void Function(String profileId)? _invalidateProfileConnection;
  final bool Function()? _enableRemoteCliDiscovery;
  final RemoteCliPathCache? _remoteCliPathCache;

  /// Single-flight: bootstrapHomeIndex, prepareInteractiveShell, and
  /// reconnectHomeSshIfNeeded all call [load] concurrently on boot; coalescing
  /// them collapses three repository reads into one.
  Future<void>? _loadFuture;

  /// Monotonic token for in-flight CLI path discoveries. [saveProfile] and
  /// [selectProfile] bump it, so a discovery that was already suspended at an
  /// await when the profile changed discards its results instead of caching
  /// and applying paths that belong to a superseded host/selection.
  int _discoveryGeneration = 0;

  Future<void> load() => _loadFuture ??= _doLoad().whenComplete(() {
    _loadFuture = null;
  });

  Future<void> _doLoad() async {
    emit(state.copyWith(isLoading: true));
    final profiles = await _profileRepository.loadAll();
    final persistedSelectedId = await _profileRepository
        .loadSelectedProfileId();
    final selectedId = profiles.isNotEmpty
        ? (_selectExistingProfileId(
            profiles,
            state.selectedProfileId.isNotEmpty
                ? state.selectedProfileId
                : persistedSelectedId,
          ))
        : '';
    if (selectedId != persistedSelectedId) {
      await _profileRepository.saveSelectedProfileId(selectedId);
    }
    emit(
      state.copyWith(
        profiles: profiles,
        selectedProfileId: selectedId,
        isLoading: false,
      ),
    );
    final selected = state.selectedProfile;
    if (selected != null) {
      // Discovery probes several shells per CLI over SSH; it must not block
      // the load (and thus boot). Cached paths apply immediately below, the
      // refresh keeps running in the background.
      unawaited(_discoverRemoteCliPath(selected));
    }
  }

  String _selectExistingProfileId(List<SshProfile> profiles, String candidate) {
    if (candidate.isNotEmpty && profiles.any((p) => p.id == candidate)) {
      return candidate;
    }
    return profiles.first.id;
  }

  Future<void> selectProfile(String profileId) async {
    if (!state.profiles.any((p) => p.id == profileId)) return;
    final profile = state.profiles.firstWhere((p) => p.id == profileId);
    await _profileRepository.saveSelectedProfileId(profileId);
    emit(state.copyWith(selectedProfileId: profileId));
    // A discovery still in flight for the previously selected profile must
    // not apply its paths after this selection.
    _discoveryGeneration++;
    unawaited(_discoverRemoteCliPath(profile));
  }

  Future<void> saveProfile(SshProfile profile) async {
    // A changed connection identity (host/port/user/auth) means cached CLI
    // paths may belong to a different machine — drop them before the reload
    // below re-discovers in the background.
    final existing = state.profiles
        .where((p) => p.id == profile.id)
        .firstOrNull;
    if (existing != null &&
        sshHomeConnectionFingerprint(existing) !=
            sshHomeConnectionFingerprint(profile)) {
      await _remoteCliPathCache?.invalidate(profile.id);
    }
    // The reload below re-discovers for the updated profile; a discovery
    // still in flight for the old connection must not cache or apply its
    // paths (it would resurrect the just-invalidated entry).
    _discoveryGeneration++;
    _invalidateProfileConnection?.call(profile.id);
    await _profileRepository.save(profile);
    await load();
  }

  Future<void> deleteProfile(String profileId) async {
    _invalidateProfileConnection?.call(profileId);
    try {
      await _credentialStore.deleteAll(profileId);
    } on Object catch (error, stackTrace) {
      // Profile metadata must still be removed when the OS keyring is locked
      // (e.g. Linux KeyringLocked) so the targets list can refresh.
      Logger().w(
        'Failed to delete SSH credentials for $profileId',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _profileRepository.delete(profileId);
    await load();
  }

  Future<void> updatePathCache(
    String profileId, {
    required String home,
    required String appDataRoot,
  }) async {
    final existing =
        state.profiles.where((p) => p.id == profileId).firstOrNull;
    if (existing == null) return;
    final next = existing.copyWith(
      lastHome: home,
      lastAppDataRoot: appDataRoot,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _profileRepository.save(next);
    emit(
      state.copyWith(
        profiles: [
          for (final p in state.profiles) p.id == profileId ? next : p,
        ],
      ),
    );
  }

  Future<void> _discoverRemoteCliPath(SshProfile profile) async {
    final locate = _locateRemoteCliPaths;
    final apply = _onRemoteCliLocated;
    if (_enableRemoteCliDiscovery?.call() != true ||
        locate == null ||
        apply == null) {
      return;
    }
    final generation = _discoveryGeneration;
    final cache = _remoteCliPathCache;
    if (cache != null) {
      try {
        final cached = await cache.load(profile.id);
        if (_staleDiscovery(generation, profile)) return;
        if (cached.isNotEmpty) {
          for (final entry in cached.entries) {
            if (_staleDiscovery(generation, profile)) return;
            await apply(entry.key, entry.value);
          }
          return;
        }
      } on Object catch (error, stackTrace) {
        // Cache read failures fall through to a live probe below.
        Logger().w(
          'Remote CLI cache read failed for ${profile.hostIdentifier}, '
          'falling back to a live probe',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    try {
      final located = await locate(profile);
      if (_staleDiscovery(generation, profile)) return;
      if (cache != null && located.isNotEmpty) {
        await cache.save(profile.id, located);
      }
      for (final entry in located.entries) {
        if (_staleDiscovery(generation, profile)) return;
        await apply(entry.key, entry.value);
      }
    } on Object catch (error, stackTrace) {
      Logger().w(
        'Remote CLI discovery failed for ${profile.hostIdentifier}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// True when [saveProfile]/[selectProfile] superseded the discovery that
  /// captured [generation] — its remaining results must be dropped.
  bool _staleDiscovery(int generation, SshProfile profile) {
    if (_discoveryGeneration == generation) return false;
    Logger().w(
      'Discarded stale remote CLI discovery for ${profile.hostIdentifier}',
    );
    return true;
  }
}
