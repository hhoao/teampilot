import 'dart:async';
import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../models/install_job/install_job_key.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';

const jobLogMaxRingLines = 2000;
const jobLogMaxLineChars = 4096;
const jobLogMaxFileBytes = 5 * 1024 * 1024;
const jobLogMaxFiles = 20;
const jobLogMaxAge = Duration(days: 7);

final _ansiPattern = RegExp(
  r'\x1B\[[0-?]*[ -/]*[@-~]|\x1B\][^\x07]*(?:\x07|\x1B\\)',
);

int _fnv1a32(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

final class JobLogWriter {
  JobLogWriter._(this._owner, this._token);

  final JobLogStore _owner;
  final String _token;

  void line(String text) => _owner._append(_token, text);

  Future<void> close() => _owner._close(_token);
}

final class JobLogStore {
  JobLogStore({
    required String appDataRoot,
    Filesystem? fs,
    DateTime Function()? now,
  }) : _fs = fs ?? LocalFilesystem(),
       _now = now ?? DateTime.now,
       _dir = p.join(appDataRoot, 'logs', 'install-jobs') {
    unawaited(purge());
  }

  final Filesystem _fs;
  final DateTime Function() _now;
  final String _dir;
  final Map<String, _LiveJobLog> _live = {};

  String tokenFor(InstallJobKey key) {
    final raw = key.activityId;
    final sanitized = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final hash = _fnv1a32(raw).toRadixString(16).padLeft(8, '0');
    return '$sanitized-$hash';
  }

  JobLogWriter begin({required InstallJobKey key, required String title}) {
    final token = tokenFor(key);
    final log = _LiveJobLog(path: _pathFor(token));
    _live[token] = log;
    final stamp = _now().toIso8601String();
    final header = '[start] $stamp — $title';
    log.lines.add(header);
    log.controller.add(header);
    final chunk = '$header\n';
    final headerBytes = utf8.encode(chunk);
    log.bytes = headerBytes.length;
    log.fileChain = _fs.writeBytes(log.path, headerBytes).catchError((
      Object error,
    ) {
      log.dropped = true;
      AppLogger.instance.w(
        '[job-log] write failed for ${log.path}',
        error: error,
      );
    });
    return JobLogWriter._(this, token);
  }

  bool isLive(String token) => _live.containsKey(token);

  Stream<String> follow(String token) {
    final log = _live[token];
    if (log == null) return const Stream<String>.empty();
    return log.subscribe();
  }

  Future<List<String>> read(String token) async {
    final raw = await _fs.readString(_pathFor(token));
    if (raw == null || raw.isEmpty) return const <String>[];
    return const LineSplitter().convert(raw);
  }

  Future<void> purge() async {
    try {
      final entries = await _fs.listDir(_dir);
      final files = <(String, DateTime)>[];
      for (final entry in entries) {
        if (entry.isDirectory) continue;
        final path = p.join(_dir, entry.name);
        final stat = await _fs.stat(path);
        if (!stat.isFile) continue;
        files.add((path, stat.mtime ?? _now()));
      }
      final cutoff = _now().subtract(jobLogMaxAge);
      for (final entry in files) {
        if (entry.$2.isBefore(cutoff)) {
          await _fs.removeRecursive(entry.$1);
        }
      }
      final alive = [
        for (final entry in files)
          if (!entry.$2.isBefore(cutoff)) entry,
      ]..sort((a, b) => b.$2.compareTo(a.$2));
      for (final entry in alive.skip(jobLogMaxFiles)) {
        await _fs.removeRecursive(entry.$1);
      }
    } on Object {
      // Purge is best effort; a missing dir or locked file must not break boot.
    }
  }

  String _pathFor(String token) => p.join(_dir, '$token.log');

  void _append(String token, String text) {
    final log = _live[token];
    if (log == null) return;
    final cleaned = text
        .replaceAll(_ansiPattern, '')
        .split('\r')
        .last
        .trimRight();
    if (cleaned.isEmpty) return;
    final lineText = cleaned.length > jobLogMaxLineChars
        ? cleaned.substring(0, jobLogMaxLineChars)
        : cleaned;

    log.lines.add(lineText);
    if (log.lines.length > jobLogMaxRingLines) log.lines.removeAt(0);
    log.controller.add(lineText);

    if (log.dropped) return;
    final chunk = '$lineText\n';
    // Encode once: the budget is in bytes, not UTF-16 code units, so CJK
    // output cannot overshoot the 5 MB cap by the encoding ratio.
    final bytes = utf8.encode(chunk);
    if (log.bytes + bytes.length > jobLogMaxFileBytes) {
      log.dropped = true;
      log.fileChain = log.fileChain
          .then((_) => _fs.appendBytes(log.path, utf8.encode('[truncated]\n')))
          .catchError((Object _) {});
      return;
    }
    log.bytes += bytes.length;
    log.fileChain = log.fileChain
        .then((_) => _fs.appendBytes(log.path, bytes))
        .catchError((Object error) {
          log.dropped = true;
          AppLogger.instance.w(
            '[job-log] write failed for ${log.path}',
            error: error,
          );
        });
  }

  Future<void> _close(String token) async {
    final log = _live.remove(token);
    if (log == null) return;
    await log.fileChain;
    await log.controller.close();
  }
}

final class _LiveJobLog {
  _LiveJobLog({required this.path});

  final String path;
  final List<String> lines = <String>[];
  final StreamController<String> controller =
      StreamController<String>.broadcast();
  Future<void> fileChain = Future<void>.value();
  int bytes = 0;
  bool dropped = false;

  Stream<String> subscribe() async* {
    yield* Stream<String>.fromIterable(List<String>.of(lines));
    yield* controller.stream;
  }
}
