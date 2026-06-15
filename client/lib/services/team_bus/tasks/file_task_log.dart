import 'dart:convert';

import '../../io/filesystem.dart';
import '../../io/local_filesystem.dart';
import 'task_log.dart';
import 'team_task.dart';

/// JSONL append-only 任务日志：`{queueRoot}/tasks.jsonl`（全队单文件）。
///
/// 每行一个事件：
/// - 入队:   `{"t":"add","seq":N,"id":...,"title":...,"brief":...,"by":...,"deps":[...],"createdAt":N}`
/// - 认领:   `{"t":"claim","id":...,"by":...,"at":N}`
/// - 变更:   `{"t":"update","id":...,"status":...,"result":...,"at":N}`
/// - 回收:   `{"t":"reclaim","id":...,"at":N}`
///
/// 全部纯追加（O(1)），无整文件重写；[load] 回放重建任务表。
class FileTaskLog implements TaskLog {
  FileTaskLog({required this.queueRoot, Filesystem? fs})
    : _fs = fs ?? LocalFilesystem();

  final String queueRoot;
  final Filesystem _fs;
  Future<void> _lock = Future<void>.value();

  String get _file => _fs.pathContext.join(queueRoot, 'tasks.jsonl');

  Future<void> _append(Map<String, Object?> event) {
    final prev = _lock;
    final next = prev.then((_) async {
      await _fs.ensureDir(queueRoot);
      await _fs.appendString(_file, '${jsonEncode(event)}\n');
    });
    _lock = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<void> appendAdd(TeamTask task) {
    return _append({
      't': 'add',
      'seq': task.seq,
      'id': task.id,
      'title': task.title,
      'brief': task.brief,
      'by': task.createdBy,
      'deps': task.dependsOn,
      'createdAt': task.createdAt,
      'reqCaps': task.requiredCapabilities.toList(),
      'prefCaps': task.preferredCapabilities.toList(),
      'assignee': task.preferredAssignee,
      'stage': task.routing.stage.name,
      'escalatedAt': task.routing.escalatedAt,
      'reserveWindowMs': task.routing.reserveWindowMs,
      'widenAfterMs': task.routing.widenAfterMs,
      'openAfterMs': task.routing.openAfterMs,
    });
  }

  @override
  Future<void> appendClaim(String taskId, String assignee, int at) {
    return _append({'t': 'claim', 'id': taskId, 'by': assignee, 'at': at});
  }

  @override
  Future<void> appendUpdate(
    String taskId,
    TaskStatus status,
    String? result,
    int at,
  ) {
    return _append({
      't': 'update',
      'id': taskId,
      'status': status.name,
      'result': result,
      'at': at,
    });
  }

  @override
  Future<void> appendReclaim(String taskId, int at) {
    return _append({'t': 'reclaim', 'id': taskId, 'at': at});
  }

  @override
  Future<void> appendEscalate(String taskId, RoutingStage stage, int at) {
    return _append(
        {'t': 'escalate', 'id': taskId, 'stage': stage.name, 'at': at});
  }

  @override
  Future<List<TeamTask>> load() async {
    final text = await _fs.readString(_file);
    if (text == null || text.trim().isEmpty) return <TeamTask>[];
    final byId = <String, TeamTask>{};
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
      final e = Map<String, Object?>.from(decoded);
      final id = e['id'] as String?;
      if (id == null) continue;
      switch (e['t']) {
        case 'add':
          byId[id] = TeamTask(
            id: id,
            seq: (e['seq'] as num?)?.toInt() ?? 0,
            title: e['title'] as String? ?? '',
            brief: e['brief'] as String? ?? '',
            createdBy: e['by'] as String? ?? '',
            createdAt: (e['createdAt'] as num?)?.toInt() ?? 0,
            dependsOn: [
              for (final d in (e['deps'] as List?) ?? const [])
                if (d is String) d,
            ],
            requiredCapabilities: {
              for (final c in (e['reqCaps'] as List?) ?? const [])
                if (c is String) c,
            },
            preferredCapabilities: {
              for (final c in (e['prefCaps'] as List?) ?? const [])
                if (c is String) c,
            },
            preferredAssignee: e['assignee'] as String?,
            routing: RoutingPolicy(
              stage: RoutingPolicy.parseStage(e['stage'] as String?),
              escalatedAt: (e['escalatedAt'] as num?)?.toInt() ?? 0,
              reserveWindowMs:
                  (e['reserveWindowMs'] as num?)?.toInt() ?? 45 * 1000,
              widenAfterMs: (e['widenAfterMs'] as num?)?.toInt() ?? 120 * 1000,
              openAfterMs: (e['openAfterMs'] as num?)?.toInt() ?? 300 * 1000,
            ),
          );
        case 'claim':
          final t = byId[id];
          if (t != null) {
            byId[id] = t.copyWith(
              status: TaskStatus.claimed,
              assignee: e['by'] as String?,
              claimedAt: (e['at'] as num?)?.toInt(),
            );
          }
        case 'update':
          final t = byId[id];
          if (t != null) {
            byId[id] = t.copyWith(
              status: TaskStatus.parse(e['status'] as String?),
              result: e['result'] as String?,
              finishedAt: (e['at'] as num?)?.toInt(),
            );
          }
        case 'reclaim':
          final t = byId[id];
          if (t != null) byId[id] = t.copyWith(status: TaskStatus.pending);
        case 'escalate':
          final t = byId[id];
          if (t != null) {
            byId[id] = t.copyWith(
              routing: t.routing.copyWith(
                stage: RoutingPolicy.parseStage(e['stage'] as String?),
                escalatedAt: (e['at'] as num?)?.toInt(),
              ),
            );
          }
      }
    }
    return byId.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
  }
}
