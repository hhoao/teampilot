import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/team_config.dart';

enum ConfigSection { members, layout, llm }

class ConfigState extends Equatable {
  const ConfigState(
      {this.section = ConfigSection.layout, this.selectedMemberId = ''});

  final ConfigSection section;
  final String selectedMemberId;

  String get title => switch (section) {
        ConfigSection.members => 'Member Configuration',
        ConfigSection.layout => 'Layout Configuration',
        ConfigSection.llm => 'LLM Configuration',
      };

  String get breadcrumb => switch (section) {
        ConfigSection.members => 'Config / Members',
        ConfigSection.layout => 'Config / Layout',
        ConfigSection.llm => 'Config / LLM',
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

  void syncTeam(TeamConfig team) {
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
    emit(state.copyWith(
        selectedMemberId: memberId, section: ConfigSection.members));
  }
}
