import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/session.dart';
import '../services/app_storage.dart';

class SessionRepository {
  const SessionRepository();

  String get _baseDir => AppStorage.flashskyaiDir;

  String get _historyPath => p.join(_baseDir, 'history.jsonl');

  String get _sessionsDir => p.join(_baseDir, 'sessions');

  Future<List<FlashskySession>> loadSessions() async {
    final sessions = <FlashskySession>{};

    // Primary source: active PID files in sessions/
    try {
      final dir = Directory(_sessionsDir);
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

  Future<FlashskySession> createSession(
    String cwd, {
    String sessionTeam = '',
  }) async {
    final sessionId = const Uuid().v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final session = FlashskySession(
      sessionId: sessionId,
      cwd: cwd,
      startedAt: nowMs,
      kind: 'interactive',
      entrypoint: 'cli',
      display: FlashskySession.kDefaultDisplayTitle,
      sessionTeam: sessionTeam,
    );
    await Directory(_sessionsDir).create(recursive: true);
    final file = File(p.join(_sessionsDir, '$sessionId.json'));
    await file.writeAsString(jsonEncode(session.toJson()));
    return session;
  }

  Future<void> renameSession(String sessionId, String newName) async {
    final file = File(p.join(_sessionsDir, '$sessionId.json'));
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, Object?>;
        json['display'] = newName;
        await file.writeAsString(jsonEncode(json));
      } on Object {
        // best effort
      }
    }
  }

  Future<void> updateSessionTeam(String sessionId, String sessionTeam) async {
    final file = File(p.join(_sessionsDir, '$sessionId.json'));
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, Object?>;
        json['sessionTeam'] = sessionTeam;
        await file.writeAsString(jsonEncode(json));
      } on Object {
        // best effort
      }
    }
  }

  Future<void> clearAllSessionTeams() async {
    try {
      final dir = Directory(_sessionsDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            try {
              final content = await entity.readAsString();
              final json = jsonDecode(content) as Map<String, Object?>;
              json.remove('sessionTeam');
              await entity.writeAsString(jsonEncode(json));
            } on Object {
              // best effort per file
            }
          }
        }
      }
    } on Object {
      // directory operation failed
    }
  }

  Future<void> deleteSession(String sessionId) async {
    final file = File(p.join(_sessionsDir, '$sessionId.json'));
    if (await file.exists()) {
      try {
        await file.delete();
      } on Object {
        // best effort
      }
    }
  }

  Future<List<FlashskySession>> _loadFromHistory() async {
    final file = File(_historyPath);
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
            final sessionTeam = json['sessionTeam'] as String? ?? '';
            if (sessionTeam.isNotEmpty) {
              builder.sessionTeam = sessionTeam;
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
        .map(
          (b) => FlashskySession(
            sessionId: b.sessionId,
            cwd: b.cwd,
            startedAt: b.startedAt,
            display: b.display,
            kind: 'interactive',
            entrypoint: 'cli',
            sessionTeam: b.sessionTeam,
          ),
        )
        .toList();
  }
}

class _SessionBuilder {
  _SessionBuilder({required this.sessionId});

  final String sessionId;
  String cwd = '';
  int startedAt = 0;
  String display = '';
  String sessionTeam = '';
}
