import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';

enum ConfigSection { layout, session, cli, aiFeatures, about, logs }

class ConfigState extends Equatable {
  const ConfigState({
    this.section = ConfigSection.layout,
    this.selectedMemberId = '',
  });

  final ConfigSection section;
  final String selectedMemberId;

  String get title => switch (section) {
    ConfigSection.layout => 'Layout Configuration',
    ConfigSection.session => 'Session Configuration',
    ConfigSection.cli => 'CLI Configuration',
    ConfigSection.aiFeatures => 'AI Features',
    ConfigSection.about => 'About',
    ConfigSection.logs => 'Logs',
  };

  String get breadcrumb => switch (section) {
    ConfigSection.layout => 'Config / Layout',
    ConfigSection.session => 'Config / Session',
    ConfigSection.cli => 'Config / CLI',
    ConfigSection.aiFeatures => 'Config / AI Features',
    ConfigSection.about => 'Config / About',
    ConfigSection.logs => 'Config / Logs',
  };

  ConfigState copyWith({ConfigSection? section, String? selectedMemberId}) {
    return ConfigState(
      section: section ?? this.section,
      selectedMemberId: selectedMemberId ?? this.selectedMemberId,
    );
  }

  @override
  List<Object?> get props => [section, selectedMemberId];
}

class ConfigCubit extends Cubit<ConfigState> {
  ConfigCubit() : super(const ConfigState());

  void selectSection(ConfigSection section) {
    if (state.section == section) return;
    emit(state.copyWith(section: section));
  }

  void syncTeam(TeamProfile team) {
    if (team.members.isEmpty) {
      if (state.selectedMemberId.isEmpty) return;
      emit(state.copyWith(selectedMemberId: ''));
      return;
    }
    if (team.members.any((m) => m.id == state.selectedMemberId)) return;
    emit(state.copyWith(selectedMemberId: team.members.first.id));
  }

  void selectMember(String memberId) {
    if (state.selectedMemberId == memberId) return;
    emit(state.copyWith(selectedMemberId: memberId));
  }
}
