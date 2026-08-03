import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/team/claude_team_roster_service.dart';

import 'native_roster_assertions.dart';

void main() {
  late Directory tmp;
  late String claudeDir;
  const cliTeamName = 't-1';

  const expectedNames = ['team-lead', 'developer-0', 'developer-1'];
  const expectedAgentTypes = {
    'team-lead': 'team-lead',
    'developer-0': 'developer',
    'developer-1': 'developer',
  };

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('native_roster_assertions_');
    claudeDir = tmp.path;
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  Future<void> writeMinimalRoster({
    List<String> names = expectedNames,
    Map<String, String> agentTypes = expectedAgentTypes,
    Iterable<String> inboxMemberIds = const ['developer-0'],
  }) async {
    final rosterDir = claudeTeamRosterDir(
      claudeDir: claudeDir,
      cliTeamName: cliTeamName,
    );
    await Directory(rosterDir).create(recursive: true);

    final members = [
      for (final name in names)
        {
          'name': name,
          'agentType': agentTypes[name] ?? name,
        },
    ];
    await File(p.join(rosterDir, 'config.json')).writeAsString(
      jsonEncode({'name': cliTeamName, 'members': members}),
    );

    final inboxDir = Directory(p.join(rosterDir, 'inboxes'));
    await inboxDir.create(recursive: true);
    for (final memberId in inboxMemberIds) {
      final slug = ClaudeTeamRosterService.safeClaudePathSegment(memberId);
      await File(p.join(inboxDir.path, '$slug.json')).writeAsString('[]');
    }
  }

  test('happy path: roster pods and inbox assertions pass', () async {
    await writeMinimalRoster();

    expectClaudeRosterPods(
      claudeDir: claudeDir,
      cliTeamName: cliTeamName,
      expectedNames: expectedNames,
      expectedAgentTypes: expectedAgentTypes,
    );
    expectClaudeInboxExists(
      claudeDir: claudeDir,
      cliTeamName: cliTeamName,
      memberId: 'developer-0',
    );
    expectClaudeInboxAbsent(
      claudeDir: claudeDir,
      cliTeamName: cliTeamName,
      memberId: 'developer',
    );
  });

  test('expectClaudeRosterPods fails on wrong member names', () async {
    await writeMinimalRoster(names: ['team-lead', 'developer-0']);

    expect(
      () => expectClaudeRosterPods(
        claudeDir: claudeDir,
        cliTeamName: cliTeamName,
        expectedNames: expectedNames,
        expectedAgentTypes: expectedAgentTypes,
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  test('expectClaudeRosterPods fails when agentType leaks pod id', () async {
    await writeMinimalRoster(
      agentTypes: {
        'team-lead': 'team-lead',
        'developer-0': 'developer-0',
        'developer-1': 'developer',
      },
    );

    expect(
      () => expectClaudeRosterPods(
        claudeDir: claudeDir,
        cliTeamName: cliTeamName,
        expectedNames: expectedNames,
        expectedAgentTypes: expectedAgentTypes,
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  test('expectClaudeInboxAbsent for type id when only pod inbox exists', () async {
    await writeMinimalRoster(inboxMemberIds: const ['developer-0']);

    expectClaudeInboxExists(
      claudeDir: claudeDir,
      cliTeamName: cliTeamName,
      memberId: 'developer-0',
    );
    expectClaudeInboxAbsent(
      claudeDir: claudeDir,
      cliTeamName: cliTeamName,
      memberId: 'developer',
    );
  });
}
