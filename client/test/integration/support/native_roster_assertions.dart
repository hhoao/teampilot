import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/team/claude_team_roster_service.dart';

String claudeTeamRosterDir({
  required String claudeDir,
  required String cliTeamName,
}) {
  return p.join(
    claudeDir,
    'teams',
    ClaudeTeamRosterService.safeClaudePathSegment(cliTeamName),
  );
}

String claudeInboxPath({
  required String claudeDir,
  required String cliTeamName,
  required String memberId,
}) {
  return p.join(
    claudeTeamRosterDir(claudeDir: claudeDir, cliTeamName: cliTeamName),
    'inboxes',
    '${ClaudeTeamRosterService.safeClaudePathSegment(memberId)}.json',
  );
}

Map<String, Object?> readClaudeRosterConfig({
  required String claudeDir,
  required String cliTeamName,
}) {
  final configPath = p.join(
    claudeTeamRosterDir(claudeDir: claudeDir, cliTeamName: cliTeamName),
    'config.json',
  );
  final file = File(configPath);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'Claude roster config missing: $configPath',
  );
  final decoded = jsonDecode(file.readAsStringSync());
  expect(decoded, isA<Map>(), reason: 'Claude roster config is not a JSON object');
  return Map<String, Object?>.from(decoded as Map);
}

void expectClaudeRosterPods({
  required String claudeDir,
  required String cliTeamName,
  required List<String> expectedNames,
  required Map<String, String> expectedAgentTypes,
}) {
  final config = readClaudeRosterConfig(
    claudeDir: claudeDir,
    cliTeamName: cliTeamName,
  );
  final members = config['members'];
  expect(
    members,
    isA<List>(),
    reason: 'Claude roster config has no members list',
  );

  final rows = [
    for (final item in members as List)
      if (item is Map) Map<String, Object?>.from(item),
  ];
  final actualNames = rows.map((row) => row['name']?.toString() ?? '').toList();
  expect(
    actualNames,
    expectedNames,
    reason: 'Claude roster member names mismatch',
  );

  for (final name in expectedNames) {
    final expectedType = expectedAgentTypes[name];
    expect(
      expectedType,
      isNotNull,
      reason: 'Missing expectedAgentTypes for $name',
    );
    final row = rows.firstWhere(
      (entry) => entry['name'] == name,
      orElse: () => const {},
    );
    expect(row, isNotEmpty, reason: 'Claude roster missing member row: $name');
    expect(
      row['agentType'],
      expectedType,
      reason: 'Claude roster agentType for $name',
    );
  }
}

void expectClaudeInboxExists({
  required String claudeDir,
  required String cliTeamName,
  required String memberId,
}) {
  final path = claudeInboxPath(
    claudeDir: claudeDir,
    cliTeamName: cliTeamName,
    memberId: memberId,
  );
  expect(
    File(path).existsSync(),
    isTrue,
    reason: 'Claude inbox missing: $path',
  );
}

void expectClaudeInboxAbsent({
  required String claudeDir,
  required String cliTeamName,
  required String memberId,
}) {
  final path = claudeInboxPath(
    claudeDir: claudeDir,
    cliTeamName: cliTeamName,
    memberId: memberId,
  );
  expect(
    File(path).existsSync(),
    isFalse,
    reason: 'Claude inbox should be absent: $path',
  );
}
