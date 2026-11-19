import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/connection/catalog_entry.dart';
import '../models/ssh_profile.dart';
import '../repositories/plane_ssh_profile_repository.dart';

/// Read-only view of the machines this home plane lists **and** this device can
/// reach. Entries without a local connection are omitted: they exist on the
/// plane but have no dial plan here.
class SshServerConfigState extends Equatable {
  const SshServerConfigState({
    this.profiles = const [],
    this.needsConnection = const [],
    this.isLoading = false,
    this.error,
  });

  /// Machines the plane lists that this device can reach.
  final List<SshProfile> profiles;

  /// Machines the plane lists that this device has no dial plan for.
  final List<CatalogEntry> needsConnection;

  final bool isLoading;
  final Object? error;

  @override
  List<Object?> get props => [profiles, needsConnection, isLoading, error];
}

class SshServerConfigCubit extends Cubit<SshServerConfigState> {
  SshServerConfigCubit({required PlaneSshProfileRepository repository})
    : _repository = repository,
      super(const SshServerConfigState());

  final PlaneSshProfileRepository _repository;

  Future<void> load() async {
    emit(const SshServerConfigState(isLoading: true));
    try {
      final view = await _repository.loadView();
      emit(
        SshServerConfigState(
          profiles: view.reachable,
          needsConnection: view.needsConnection,
        ),
      );
    } on Object catch (error) {
      emit(SshServerConfigState(error: error));
    }
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }
}
