import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';

typedef BusMailRowPredicate = bool Function(Map<String, Object?> row);

String busMailFilePath({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
  required String memberId,
}) {
  final layout = WorkspaceLayout(teampilotRoot: teampilotRoot);
  final mailRoot = layout.busMailDir(workspaceId, sessionId);
  final slug = ClaudeTeamRosterService.safeClaudePathSegment(memberId);
  return p.join(mailRoot, '$slug.jsonl');
}

Future<List<Map<String, Object?>>> readBusMailLines({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
  required String memberId,
}) async {
  final file = File(
    busMailFilePath(
      teampilotRoot: teampilotRoot,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
    ),
  );
  if (!await file.exists()) return const [];

  final text = await file.readAsString();
  if (text.trim().isEmpty) return const [];

  final rows = <Map<String, Object?>>[];
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on Object {
      continue;
    }
    if (decoded is! Map) continue;
    final row = Map<String, Object?>.from(decoded);
    if (row['t'] == 'msg') {
      rows.add(row);
    }
  }
  return rows;
}

int? mailCreatedAtForContent(
  List<Map<String, Object?>> rows, {
  required String fromMemberId,
  required String content,
}) {
  for (final row in rows) {
    if (row['from'] == fromMemberId && row['content'] == content) {
      return (row['createdAt'] as num?)?.toInt();
    }
  }
  return null;
}

Future<bool> waitForBusMail({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
  required String memberId,
  required BusMailRowPredicate where,
  Duration timeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 200),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final rows = await readBusMailLines(
      teampilotRoot: teampilotRoot,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
    );
    if (rows.any(where)) return true;
    await Future<void>.delayed(pollInterval);
  }
  return false;
}

Future<void> dumpBusMailDiagnostics({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
  required Iterable<String> memberIds,
}) async {
  for (final memberId in memberIds) {
    final path = busMailFilePath(
      teampilotRoot: teampilotRoot,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
    );
    // ignore: avoid_print
    print('--- bus mail: $memberId -> $path');
    final file = File(path);
    if (await file.exists()) {
      // ignore: avoid_print
      print(await file.readAsString());
    } else {
      // ignore: avoid_print
      print('(file does not exist)');
    }
  }
}
