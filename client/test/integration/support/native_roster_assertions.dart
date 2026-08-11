import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/claude/team_roster_service.dart';

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

int readClaudeInboxUnreadCount({
  required String claudeDir,
  required String cliTeamName,
  required String memberId,
}) {
  final path = claudeInboxPath(
    claudeDir: claudeDir,
    cliTeamName: cliTeamName,
    memberId: memberId,
  );
  final file = File(path);
  if (!file.existsSync()) return 0;
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! List) return 0;
  var unread = 0;
  for (final item in decoded) {
    if (item is Map && item['read'] == false) unread++;
  }
  return unread;
}

void expectClaudeInboxUnread({
  required String claudeDir,
  required String cliTeamName,
  required String memberId,
  int minUnread = 1,
}) {
  final unread = readClaudeInboxUnreadCount(
    claudeDir: claudeDir,
    cliTeamName: cliTeamName,
    memberId: memberId,
  );
  expect(
    unread,
    greaterThanOrEqualTo(minUnread),
    reason:
        'Claude inbox for $memberId should have ≥$minUnread unread messages',
  );
}

/// Poll until lead SendMessage lands in the pod inbox (before worker consume).
Future<void> waitForClaudeInboxUnread({
  required String claudeDir,
  required String cliTeamName,
  required String memberId,
  int minUnread = 1,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final unread = readClaudeInboxUnreadCount(
      claudeDir: claudeDir,
      cliTeamName: cliTeamName,
      memberId: memberId,
    );
    if (unread >= minUnread) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  final path = claudeInboxPath(
    claudeDir: claudeDir,
    cliTeamName: cliTeamName,
    memberId: memberId,
  );
  final raw = File(path).existsSync() ? File(path).readAsStringSync() : '';
  throw TestFailure(
    'Timed out waiting for ≥$minUnread unread inbox messages for $memberId '
    '(path=$path raw=$raw)',
  );
}
