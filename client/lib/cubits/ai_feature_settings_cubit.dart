import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/ai_feature_setting.dart';
import '../repositories/app_settings_repository.dart';

class AiFeatureSettingsState extends Equatable {
  const AiFeatureSettingsState({this.settings = const {}});

  final Map<AiFeatureId, AiFeatureSetting> settings;

  AiFeatureSetting? settingFor(AiFeatureId id) => settings[id];

  AiFeatureSettingsState copyWith({
    Map<AiFeatureId, AiFeatureSetting>? settings,
  }) => AiFeatureSettingsState(settings: settings ?? this.settings);

  @override
  List<Object?> get props => [settings];
}

class AiFeatureSettingsCubit extends Cubit<AiFeatureSettingsState> {
  AiFeatureSettingsCubit({required AppSettingsRepository repository})
    : _repository = repository,
      super(const AiFeatureSettingsState());

  final AppSettingsRepository _repository;

  Future<void> load() async {
    final loaded = await _repository.loadAiFeatureSettings();
    emit(state.copyWith(settings: loaded));
  }

  Future<void> updateSetting(AiFeatureId id, AiFeatureSetting setting) async {
    final next = Map<AiFeatureId, AiFeatureSetting>.from(state.settings);
    next[id] = setting;
    emit(state.copyWith(settings: next));
    await _repository.saveAiFeatureSetting(id, setting);
  }
}
