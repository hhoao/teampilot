import 'dart:async';
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
///
/// Note: this is inherently racy — the booted worker process consumes the
/// message within ~100ms of the write, so the poll can start after the
/// delivery already happened. Prefer [ClaudeInboxUnreadWatch] (started before
/// the compose) for deterministic delivery checks.
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

/// Tracks the peak unread count of a pod inbox while a lead dispatch is in
/// flight.
///
/// Claude workers poll their own pod inbox and consume messages within ~100ms
/// of the lead `SendMessage` write, leaving the file back at `[]`. A watcher
/// started *before* the compose observes the transient delivery regardless of
/// when the test next checks; [waitForUnread] then waits for the observed
/// peak. Stop with [stop] when done (tearDown).
class ClaudeInboxUnreadWatch {
  ClaudeInboxUnreadWatch({
    required this.claudeDir,
    required this.cliTeamName,
    required this.memberId,
    this.tick = const Duration(milliseconds: 10),
  }) {
    _timer = Timer.periodic(tick, (_) => _poll());
  }

  final String claudeDir;
  final String cliTeamName;
  final String memberId;
  final Duration tick;

  Timer? _timer;
  int _maxUnread = 0;

  /// Highest unread count observed since the watch started.
  int get maxUnread => _maxUnread;

  void _poll() {
    final unread = readClaudeInboxUnreadCount(
      claudeDir: claudeDir,
      cliTeamName: cliTeamName,
      memberId: memberId,
    );
    if (unread > _maxUnread) _maxUnread = unread;
  }

  /// Awaits until the watch observed at least [minUnread] unread messages
  /// (i.e. the lead dispatch landed in the pod inbox).
  Future<void> waitForUnread({
    int minUnread = 1,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_maxUnread >= minUnread) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
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

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
