import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../repositories/app_settings_repository.dart';

class DiscoverySettingsState extends Equatable {
  const DiscoverySettingsState({this.autoRefreshEnabled = false});

  final bool autoRefreshEnabled;

  DiscoverySettingsState copyWith({bool? autoRefreshEnabled}) =>
      DiscoverySettingsState(
        autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,
      );

  @override
  List<Object?> get props => [autoRefreshEnabled];
}

class DiscoverySettingsCubit extends Cubit<DiscoverySettingsState> {
  DiscoverySettingsCubit({required AppSettingsRepository repository})
    : _repository = repository,
      super(const DiscoverySettingsState());

  final AppSettingsRepository _repository;

  Future<void> load() async {
    final enabled = await _repository.loadDiscoveryAutoRefreshEnabled();
    emit(state.copyWith(autoRefreshEnabled: enabled));
  }

  Future<void> setAutoRefreshEnabled(bool value) async {
    emit(state.copyWith(autoRefreshEnabled: value));
    await _repository.saveDiscoveryAutoRefreshEnabled(value);
  }
}
