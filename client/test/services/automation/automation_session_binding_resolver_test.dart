import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/automation/automation_session_binding_resolver.dart';

Automation _launch({bool isPersonal = true, String? teamId}) => Automation(
  id: 'a1',
  name: 'Daily',
  action: AutomationAction.launchPrompt,
  workspaceId: 'ws1',
  isPersonal: isPersonal,
  teamId: teamId,
  presetId: isPersonal ? 'preset-1' : null,
  message: 'ping',
  preset: AutomationSchedulePreset.daily,
  hourMinute: '09:00',
  timezone: 'UTC',
  dtstartMs: 1,
  createdAtMs: 1,
  updatedAtMs: 1,
);

AppSession _session({
  required String id,
  String workspaceId = 'ws1',
  CliTool? cli = CliTool.claude,
  String sessionTeam = '',
  bool archived = false,
  SessionPurpose purpose = SessionPurpose.normal,
  int updatedAt = 0,
}) => AppSession(
  sessionId: id,
  workspaceId: workspaceId,
  display: 'Session $id',
  cli: cli,
  sessionTeam: sessionTeam,
  archived: archived,
  purpose: purpose,
  createdAt: 1,
  updatedAt: updatedAt,
);

void main() {
  test('findBoundSession resolves by id and ignores null/empty/unknown', () {
    final sessions = [_session(id: 's1'), _session(id: 's2')];
    expect(findBoundSession('s2', sessions)?.sessionId, 's2');
    expect(findBoundSession(null, sessions), isNull);
    expect(findBoundSession('  ', sessions), isNull);
    expect(findBoundSession('missing', sessions), isNull);
  });

  test('bindingCliFilter returns simple session cli with claude fallback', () {
    expect(
      bindingCliFilter(_session(id: 's1', cli: CliTool.codex)),
      CliTool.codex,
    );
    expect(bindingCliFilter(_session(id: 's1', cli: null)), CliTool.claude);
  });

  test('bindingCliFilter returns null for team sessions and null input', () {
    expect(bindingCliFilter(null), isNull);
    expect(bindingCliFilter(_session(id: 's1', sessionTeam: 'team-1')), isNull);
  });

  test('bindableSessionsFor keeps only compatible active normal sessions', () {
    final sessions = [
      _session(id: 'simple', updatedAt: 5),
      _session(id: 'other-workspace', workspaceId: 'ws2'),
      _session(id: 'archived', archived: true),
      _session(id: 'builder', purpose: SessionPurpose.teamGeneration),
      _session(id: 'team', sessionTeam: 'team-1'),
    ];
    final result = bindableSessionsFor(
      automation: _launch(),
      sessions: sessions,
    );
    expect(result.map((s) => s.sessionId).toList(), ['simple']);
  });

  test('bindableSessionsFor for team keeps matching team only', () {
    final sessions = [
      _session(id: 'simple'),
      _session(id: 'team-1-session', sessionTeam: 'team-1'),
      _session(id: 'team-2-session', sessionTeam: 'team-2'),
    ];
    final result = bindableSessionsFor(
      automation: _launch(isPersonal: false, teamId: 'team-1'),
      sessions: sessions,
    );
    expect(result.map((s) => s.sessionId).toList(), ['team-1-session']);
  });

  test('bindableSessionsFor sorts by recentlyUpdated', () {
    final sessions = [
      _session(id: 'old', updatedAt: 1),
      _session(id: 'new', updatedAt: 9),
      _session(id: 'mid', updatedAt: 5),
    ];
    final result = bindableSessionsFor(
      automation: _launch(),
      sessions: sessions,
    );
    expect(result.map((s) => s.sessionId).toList(), ['new', 'mid', 'old']);
  });
}
