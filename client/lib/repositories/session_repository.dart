import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/session.dart';

class SessionRepository {
  const SessionRepository();

  Future<String> get _baseDir async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'flashskyai');
  }

  Future<String> get _historyPath async {
    final base = await _baseDir;
    return p.join(base, 'history.jsonl');
  }

  Future<String> get _sessionsDir async {
    final base = await _baseDir;
    return p.join(base, 'sessions');
  }

  Future<List<FlashskySession>> loadSessions() async {
    final sessions = <FlashskySession>{};

    // Primary source: active PID files in sessions/
    try {
      final dir = Directory(await _sessionsDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final content = await entity.readAsString();
              final json = jsonDecode(content);
              if (json is Map<String, Object?>) {
                sessions.add(FlashskySession.fromJson(json));
              }
            } on Object {
              // skip unreadable files
            }
          }
        }
      }
    } on Object {
      // directory read failed
    }

    // Secondary source: history.jsonl for ALL sessions (active + completed)
    final historySessions = await _loadFromHistory();
    for (final s in historySessions) {
      sessions.add(s);
    }

    final list = sessions.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  Future<List<FlashskySession>> _loadFromHistory() async {
    final file = File(await _historyPath);
    if (!await file.exists()) {
      return [];
    }

    final sessionMap = <String, _SessionBuilder>{};

    try {
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        try {
          final json = jsonDecode(line);
          if (json is Map<String, Object?>) {
            final sessionId = json['sessionId'] as String? ?? '';
            final display = json['display'] as String? ?? '';
            final project = json['project'] as String? ?? '';
            final timestamp = json['timestamp'] as int? ?? 0;

            if (sessionId.isEmpty) {
              continue;
            }

            final builder = sessionMap.putIfAbsent(
              sessionId,
              () => _SessionBuilder(sessionId: sessionId),
            );
            builder.cwd = project;
            if (timestamp < builder.startedAt || builder.startedAt == 0) {
              builder.startedAt = timestamp;
            }
            if (display.isNotEmpty) {
              builder.display = display;
            }
          }
        } on FormatException {
          // skip malformed lines
        }
      }
    } on Object {
      // file unreadable
    }

    return sessionMap.values
        .map((b) => FlashskySession(
              sessionId: b.sessionId,
              cwd: b.cwd,
              startedAt: b.startedAt,
              display: b.display,
              kind: 'interactive',
              entrypoint: 'cli',
            ))
        .toList();
  }
}

class _SessionBuilder {
  _SessionBuilder({required this.sessionId});

  final String sessionId;
  String cwd = '';
  int startedAt = 0;
  String display = '';
}
