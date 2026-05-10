import 'package:flutter/foundation.dart';

import '../models/team_config.dart';
import '../services/terminal_session.dart';

class ChatController extends ChangeNotifier {
  ChatController();

  String _selectedMemberId = '';

  TerminalSession? _session;
  String? _sessionTeamId;
  String? _sessionMemberId;

  String get selectedMemberId => _selectedMemberId;

  TerminalSession? get session => _session;

  void syncTeam(TeamConfig team) {
    if (team.members.isEmpty) {
      _selectedMemberId = '';
      _killSession();
      notifyListeners();
      return;
    }
    if (team.members.any((member) => member.id == _selectedMemberId)) {
      return;
    }
    final lead = team.members.where((member) => member.name == 'team-lead');
    _selectedMemberId = lead.isEmpty ? team.members.first.id : lead.first.id;
    _killSession();
    notifyListeners();
  }

  void selectMember(String memberId) {
    if (_selectedMemberId == memberId) {
      return;
    }
    _selectedMemberId = memberId;
    _killSession();
    notifyListeners();
  }

  String selectedMemberName(TeamConfig team) {
    for (final member in team.members) {
      if (member.id == _selectedMemberId) {
        return member.name;
      }
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }

  TerminalSession ensureSession(TeamConfig team) {
    if (_session != null &&
        _sessionTeamId == team.id &&
        _sessionMemberId == _selectedMemberId) {
      return _session!;
    }

    _session?.dispose();
    _session = TerminalSession();
    _sessionTeamId = team.id;
    _sessionMemberId = _selectedMemberId;

    return _session!;
  }

  void connectSession(TeamConfig team) {
    final session = ensureSession(team);
    if (session.isRunning) {
      return;
    }

    final memberId = _selectedMemberId;
    if (memberId.isEmpty) {
      session.terminal.write('\r\n[No member selected]\r\n');
      return;
    }

    final member = team.members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => team.members.first,
    );

    session.connect(team, member);
    notifyListeners();
  }

  void disconnectSession() {
    _session?.disconnect();
    notifyListeners();
  }

  void restartSession(TeamConfig team) {
    _killSession();
    ensureSession(team);
    connectSession(team);
  }

  void addSystemMessage(String content) {
    if (_session != null) {
      _session!.terminal.write('\r\n[system] $content\r\n');
    }
  }

  void _killSession() {
    _session?.dispose();
    _session = null;
    _sessionTeamId = null;
    _sessionMemberId = null;
  }

  @override
  void dispose() {
    _killSession();
    super.dispose();
  }
}
