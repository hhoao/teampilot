import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_profile.dart';
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

class SshProfileCubit extends Cubit<SshProfileState> {
  SshProfileCubit({
    required SshProfileRepository profileRepository,
    required SshCredentialStore credentialStore,
  })  : _profileRepository = profileRepository,
        _credentialStore = credentialStore,
        super(const SshProfileState());

  final SshProfileRepository _profileRepository;
  final SshCredentialStore _credentialStore;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    final profiles = await _profileRepository.loadAll();
    final persistedSelectedId = await _profileRepository.loadSelectedProfileId();
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
    emit(state.copyWith(
      profiles: profiles,
      selectedProfileId: selectedId,
      isLoading: false,
    ));
  }

  String _selectExistingProfileId(List<SshProfile> profiles, String candidate) {
    if (candidate.isNotEmpty && profiles.any((p) => p.id == candidate)) {
      return candidate;
    }
    return profiles.first.id;
  }

  Future<void> selectProfile(String profileId) async {
    if (!state.profiles.any((p) => p.id == profileId)) return;
    await _profileRepository.saveSelectedProfileId(profileId);
    emit(state.copyWith(selectedProfileId: profileId));
  }

  Future<void> saveProfile(SshProfile profile) async {
    await _profileRepository.save(profile);
    await load();
  }

  Future<void> deleteProfile(String profileId) async {
    await _credentialStore.deleteAll(profileId);
    await _profileRepository.delete(profileId);
    await load();
  }
}
