import 'package:flutter/foundation.dart';

import '../models/team_config.dart';

enum ConfigSection { team, members, layout, llm }

class ConfigController extends ChangeNotifier {
  ConfigSection _section = ConfigSection.team;
  String _selectedMemberId = '';

  ConfigSection get section => _section;
  String get selectedMemberId => _selectedMemberId;

  void selectSection(ConfigSection section) {
    if (_section == section) {
      return;
    }
    _section = section;
    notifyListeners();
  }

  void syncTeam(TeamConfig team) {
    if (team.members.isEmpty) {
      if (_selectedMemberId.isEmpty) {
        return;
      }
      _selectedMemberId = '';
      notifyListeners();
      return;
    }
    if (team.members.any((member) => member.id == _selectedMemberId)) {
      return;
    }
    _selectedMemberId = team.members.first.id;
    notifyListeners();
  }

  void selectMember(String memberId) {
    if (_selectedMemberId == memberId) {
      return;
    }
    _selectedMemberId = memberId;
    _section = ConfigSection.members;
    notifyListeners();
  }

  String get title => switch (_section) {
    ConfigSection.team => 'Team Configuration',
    ConfigSection.members => 'Member Configuration',
    ConfigSection.layout => 'Layout Configuration',
    ConfigSection.llm => 'LLM Configuration',
  };

  String get breadcrumb => switch (_section) {
    ConfigSection.team => 'Config / Team',
    ConfigSection.members => 'Config / Members',
    ConfigSection.layout => 'Config / Layout',
    ConfigSection.llm => 'Config / LLM',
  };
}
