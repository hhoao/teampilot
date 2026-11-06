import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ssh_server_profile.dart';
import '../repositories/ssh_server_profile_repository.dart';

class SshServerConfigState extends Equatable {
  const SshServerConfigState({
    this.profiles = const [],
    this.isLoading = false,
    this.error,
  });

  final List<SshServerProfile> profiles;
  final bool isLoading;
  final Object? error;

  @override
  List<Object?> get props => [profiles, isLoading, error];
}

class SshServerConfigCubit extends Cubit<SshServerConfigState> {
  SshServerConfigCubit({required SshServerProfileRepository repository})
      : _repository = repository,
        super(const SshServerConfigState());

  final SshServerProfileRepository _repository;

  Future<void> load() async {
    emit(const SshServerConfigState(isLoading: true));
    try {
      final profiles = await _repository.loadAll();
      emit(SshServerConfigState(profiles: profiles));
    } on Object catch (error) {
      emit(SshServerConfigState(error: error));
    }
  }

  Future<void> save(SshServerProfile profile) async {
    await _repository.save(profile);
    await load();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }
}
