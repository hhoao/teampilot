import 'dart:convert';
import 'dart:io';

import 'launch_meta.dart';

/// True when [sessionId] is a single path segment.
///
/// Rejects empty ids, `.`, `..`, separators, and any embedded `..` so a
/// phone-supplied id cannot write or delete outside the spool.
bool isSafeAcpProxySessionId(String sessionId) {
  if (sessionId.isEmpty || sessionId == '.' || sessionId == '..') {
    return false;
  }
  if (sessionId.contains('..')) return false;
  if (sessionId.contains('/') || sessionId.contains('\\')) return false;
  if (sessionId.contains('\u0000')) return false;
  return true;
}

void requireSafeAcpProxySessionId(String sessionId) {
  if (isSafeAcpProxySessionId(sessionId)) return;
  throw const FormatException('session id must be one path segment');
}

/// Disk spool `<root>/acp-proxy/sessions/<sessionId>/` and its memory tail.
///
/// `meta.json` is the only file that stores launch `env`. `updates.jsonl` is
/// one JSON object per line. The tail is the suffix of those lines whose
/// UTF-8 size is at most [memoryTailBytes]. The directory is mode `0700`
/// and both files are mode `0600` on POSIX.
class AcpProxySpool {
  AcpProxySpool({required this.root, this.memoryTailBytes = 65536});

  final Directory root;
  final int memoryTailBytes;

  final Map<String, _Tail> _tails = {};

  Future<void> create({
    required String sessionId,
    required String cwd,
    required AcpProxyLaunchMeta meta,
  }) async {
    requireSafeAcpProxySessionId(sessionId);
    final dir = _sessionDirectory(sessionId);
    try {
      await dir.create(recursive: true);
      await _chmod(dir, _directoryMode);

      final metaFile = _metaFile(sessionId);
      final encoded = jsonEncode({
        'cwd': cwd,
        'cli': meta.cli,
        'executable': meta.executable,
        'args': meta.args,
        'env': meta.env,
        'permissionPolicy': meta.permissionPolicy.name,
        if (meta.authenticateMethodId != null)
          'authenticateMethodId': meta.authenticateMethodId,
      });
      await metaFile.writeAsString('$encoded\n', flush: true);
      await _chmod(metaFile, _fileMode);

      final updates = _updatesFile(sessionId);
      await updates.writeAsString('', flush: true);
      await _chmod(updates, _fileMode);
      _tails[sessionId] = _Tail();
    } on Object {
      try {
        _tails.remove(sessionId);
        if (dir.existsSync()) await dir.delete(recursive: true);
      } on Object {
        // Callers handle the original create error.
      }
      rethrow;
    }
  }

  /// Appends [update] to `updates.jsonl`. Does not write launch `env`.
  void appendUpdate(String sessionId, Map<String, Object?> update) {
    final file = _updatesFile(sessionId);
    if (!file.existsSync()) {
      throw StateError('session $sessionId has no spool');
    }
    final stored = Map<String, Object?>.from(update);
    final line = '${jsonEncode(stored)}\n';
    file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    final tail = _tails.putIfAbsent(sessionId, _Tail.new);
    tail.add(stored, utf8.encode(line).length, memoryTailBytes);
  }

  List<Map<String, Object?>> memoryTail(String sessionId) {
    final tail = _tails[sessionId];
    if (tail == null) return const [];
    return tail.updates();
  }

  Future<List<Map<String, Object?>>> readAll(String sessionId) async {
    final file = _updatesFile(sessionId);
    if (!file.existsSync()) return const [];
    final raw = await file.readAsString();
    if (raw.isEmpty) return const [];
    final updates = <Map<String, Object?>>[];
    for (final line in const LineSplitter().convert(raw)) {
      if (line.isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('spool update must be a JSON object');
      }
      updates.add(Map<String, Object?>.from(decoded));
    }
    return updates;
  }

  Future<void> delete(String sessionId) async {
    requireSafeAcpProxySessionId(sessionId);
    _tails.remove(sessionId);
    final dir = _sessionDirectory(sessionId);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  Directory _sessionDirectory(String sessionId) {
    requireSafeAcpProxySessionId(sessionId);
    return Directory('${root.path}/acp-proxy/sessions/$sessionId');
  }

  File _metaFile(String sessionId) =>
      File('${_sessionDirectory(sessionId).path}/meta.json');

  File _updatesFile(String sessionId) =>
      File('${_sessionDirectory(sessionId).path}/updates.jsonl');
}

class _Tail {
  final List<_Entry> _entries = [];
  var _bytes = 0;

  void add(Map<String, Object?> update, int bytes, int limit) {
    _entries.add(_Entry(update, bytes));
    _bytes += bytes;
    while (_entries.isNotEmpty && _bytes > limit) {
      _bytes -= _entries.removeAt(0).bytes;
    }
  }

  List<Map<String, Object?>> updates() => [
    for (final entry in _entries) Map<String, Object?>.from(entry.update),
  ];
}

class _Entry {
  _Entry(this.update, this.bytes);

  final Map<String, Object?> update;
  final int bytes;
}

const _directoryMode = '700';
const _fileMode = '600';

Future<void> _chmod(FileSystemEntity entity, String mode) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', [mode, entity.path]);
  if (result.exitCode != 0) {
    final error = '${result.stderr}'.trim();
    throw StateError(
      'chmod $mode failed for ${entity.path}${error.isEmpty ? '' : ': $error'}',
    );
  }
}
