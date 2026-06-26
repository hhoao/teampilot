import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../models/ssh_profile.dart';
import '../models/team_config.dart';
import '../repositories/ssh_credential_store.dart';
import '../repositories/ssh_profile_repository.dart';

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
typedef RemoteCliPathHandler =
    Future<void> Function(CliTool cli, String path);

class SshProfileCubit extends Cubit<SshProfileState> {
  SshProfileCubit({
    required SshProfileRepository profileRepository,
    required SshCredentialStore credentialStore,
    RemoteCliPathsLocator? locateRemoteCliPaths,
    RemoteCliPathHandler? onRemoteCliLocated,
    void Function(String profileId)? invalidateProfileConnection,
    bool Function()? enableRemoteCliDiscovery,
    Future<void> Function()? onActiveProfileChanged,
  }) : _profileRepository = profileRepository,
       _credentialStore = credentialStore,
       _locateRemoteCliPaths = locateRemoteCliPaths,
       _onRemoteCliLocated = onRemoteCliLocated,
       _invalidateProfileConnection = invalidateProfileConnection,
       _enableRemoteCliDiscovery = enableRemoteCliDiscovery,
       _onActiveProfileChanged = onActiveProfileChanged,
       super(const SshProfileState());

  final SshProfileRepository _profileRepository;
  final SshCredentialStore _credentialStore;
  final RemoteCliPathsLocator? _locateRemoteCliPaths;
  final RemoteCliPathHandler? _onRemoteCliLocated;
  final void Function(String profileId)? _invalidateProfileConnection;
  final bool Function()? _enableRemoteCliDiscovery;
  final Future<void> Function()? _onActiveProfileChanged;

  Future<void> load({bool notifyActiveProfileChanged = true}) async {
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
      await _discoverRemoteCliPath(selected);
      if (notifyActiveProfileChanged) {
        await _onActiveProfileChanged?.call();
      }
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
    await _discoverRemoteCliPath(profile);
    await _onActiveProfileChanged?.call();
  }

  Future<void> saveProfile(SshProfile profile) async {
    _invalidateProfileConnection?.call(profile.id);
    await _profileRepository.save(profile);
    await load();
  }

  Future<void> deleteProfile(String profileId) async {
    _invalidateProfileConnection?.call(profileId);
    await _credentialStore.deleteAll(profileId);
    await _profileRepository.delete(profileId);
    await load();
  }

  Future<void> _discoverRemoteCliPath(SshProfile profile) async {
    final locate = _locateRemoteCliPaths;
    final apply = _onRemoteCliLocated;
    if (_enableRemoteCliDiscovery?.call() != true ||
        locate == null ||
        apply == null) {
      return;
    }
    try {
      final located = await locate(profile);
      for (final entry in located.entries) {
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
}
