import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/services/storage/workspace_layout.dart';

typedef BusTaskRowPredicate = bool Function(Map<String, Object?> row);

String busTasksFilePath({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
}) {
  final layout = WorkspaceLayout(teampilotRoot: teampilotRoot);
  return p.join(layout.busTasksDir(workspaceId, sessionId), 'tasks.jsonl');
}

Future<List<Map<String, Object?>>> readBusTaskEvents({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
}) async {
  final file = File(
    busTasksFilePath(
      teampilotRoot: teampilotRoot,
      workspaceId: workspaceId,
      sessionId: sessionId,
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
    rows.add(Map<String, Object?>.from(decoded));
  }
  return rows;
}

String? taskIdForTitle(
  List<Map<String, Object?>> events,
  String title,
) {
  for (final row in events) {
    if (row['t'] == 'add' && row['title'] == title) {
      return row['id'] as String?;
    }
  }
  return null;
}

Future<bool> waitForBusTaskEvent({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
  required BusTaskRowPredicate where,
  Duration timeout = const Duration(seconds: 90),
  Duration pollInterval = const Duration(milliseconds: 300),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final events = await readBusTaskEvents(
      teampilotRoot: teampilotRoot,
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    if (events.any(where)) return true;
    await Future<void>.delayed(pollInterval);
  }
  return false;
}

Future<bool> waitForTaskClaimedByTitle({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
  required String title,
  required String assignee,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final events = await readBusTaskEvents(
      teampilotRoot: teampilotRoot,
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    final taskId = taskIdForTitle(events, title);
    if (taskId != null &&
        events.any(
          (row) =>
              row['t'] == 'claim' && row['id'] == taskId && row['by'] == assignee,
        )) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

int? claimTimestampForTitle(
  List<Map<String, Object?>> events,
  String title, {
  String? assignee,
}) {
  final taskId = taskIdForTitle(events, title);
  if (taskId == null) return null;
  for (final row in events) {
    if (row['t'] != 'claim' || row['id'] != taskId) continue;
    if (assignee != null && row['by'] != assignee) continue;
    return (row['at'] as num?)?.toInt();
  }
  return null;
}

int? doneTimestampForTitle(
  List<Map<String, Object?>> events,
  String title,
) {
  final taskId = taskIdForTitle(events, title);
  if (taskId == null) return null;
  for (final row in events) {
    if (row['t'] != 'update' || row['id'] != taskId) continue;
    if (row['status'] != 'done') continue;
    return (row['at'] as num?)?.toInt();
  }
  return null;
}

bool isTaskDone(List<Map<String, Object?>> events, String title) =>
    doneTimestampForTitle(events, title) != null;

Future<bool> waitForTaskDoneByTitle({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
  required String title,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final events = await readBusTaskEvents(
      teampilotRoot: teampilotRoot,
      workspaceId: workspaceId,
      sessionId: sessionId,
    );
    if (isTaskDone(events, title)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

bool isTaskClaimed(
  List<Map<String, Object?>> events,
  String title, {
  String? assignee,
}) =>
    claimTimestampForTitle(events, title, assignee: assignee) != null;

/// Asserts [title] is enqueued but not yet claimed (L1 mail-priority invariant).
void expectTaskPendingNotClaimed(
  List<Map<String, Object?>> events,
  String title,
) {
  final taskId = taskIdForTitle(events, title);
  if (taskId == null) {
    throw StateError('Task "$title" was never enqueued');
  }
  if (events.any((row) => row['t'] == 'claim' && row['id'] == taskId)) {
    throw StateError('Task "$title" was already claimed');
  }
}

/// Asserts mail to the worker arrived strictly before task claim (jsonl clocks).
void expectClaimAfterMail({
  required int mailCreatedAt,
  required int claimAt,
  String? title,
}) {
  if (claimAt <= mailCreatedAt) {
    throw StateError(
      'Task${title == null ? '' : ' "$title"'} claim at $claimAt '
      'is not after mail at $mailCreatedAt',
    );
  }
}

Future<void> dumpBusTaskDiagnostics({
  required String teampilotRoot,
  required String workspaceId,
  required String sessionId,
}) async {
  final path = busTasksFilePath(
    teampilotRoot: teampilotRoot,
    workspaceId: workspaceId,
    sessionId: sessionId,
  );
  // ignore: avoid_print
  print('--- bus tasks: $path');
  final file = File(path);
  if (await file.exists()) {
    // ignore: avoid_print
    print(await file.readAsString());
  } else {
    // ignore: avoid_print
    print('(file does not exist)');
  }
}
