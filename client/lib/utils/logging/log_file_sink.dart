import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

import 'app_log_level.dart';

class LogFileSink {
  LogFileSink({
    required this.logsRoot,
    required this.level,
    required this.clock,
    required this.maxLogFileSize,
    required this.onWriteError,
  });

  final String logsRoot;
  final AppLogLevel level;
  final DateTime Function() clock;
  final int maxLogFileSize;
  final void Function(Object error)? onWriteError;

  Directory get directory => Directory(p.join(logsRoot, level.directoryName));

  File get latestFile => File(p.join(directory.path, 'latest.log'));

  _FlushingFileOutput? _output;
  DateTime _openedOn = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> init() async {
    await directory.create(recursive: true);
    final latest = latestFile;
    if (await latest.exists()) {
      final modified = await latest.lastModified();
      final today = _dateOnly(clock());
      final staleDay = _dateOnly(modified) != today;
      final tooBig = await latest.length() > maxLogFileSize;
      if (staleDay || tooBig) {
        _openedOn = _dateOnly(modified);
        _output = _FlushingFileOutput(file: latest, onWriteError: onWriteError);
        await _output!.init();
        await rotate();
        return;
      }
    }
    await _openLatest(_dateOnly(clock()));
  }

  void output(OutputEvent event) {
    if (event.level.value < level.toLoggerLevel().value) return;
    _output?.output(event);
  }

  Future<void> flush() => _output?.flush() ?? Future<void>.value();

  Future<void> destroy() async {
    await _output?.destroy();
    _output = null;
  }

  Future<bool> rotateIfNeeded() async {
    final file = _output?.file;
    if (file == null) return true;
    if (!await file.exists()) return true;
    final today = _dateOnly(clock());
    final tooBig = await file.length() > maxLogFileSize;
    if (!tooBig && today == _openedOn) return true;
    return rotate();
  }

  /// `true` = rotated or nothing to do; `false` = rename failed, re-opened
  /// the current `latest.log`.
  Future<bool> rotate() async {
    final current = _output;
    if (current == null) return true;
    await current.destroy();
    _output = null;
    final latest = latestFile;
    if (await latest.exists() && await latest.length() > 0) {
      final date = _openedOn;
      final y = date.year.toString().padLeft(4, '0');
      final mo = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      var archive = File(p.join(directory.path, 'app_$y-$mo-$d.log'));
      if (await archive.exists()) {
        archive = File(
          p.join(
            directory.path,
            'app_$y-$mo-${d}_${clock().millisecondsSinceEpoch}.log',
          ),
        );
      }
      try {
        await latest.rename(archive.path);
      } on Object {
        await _openLatest(_openedOn);
        return false;
      }
    }
    await _openLatest(_dateOnly(clock()));
    return true;
  }

  Future<void> _openLatest(DateTime openedOn) async {
    _openedOn = openedOn;
    final latest = latestFile;
    if (!await latest.exists()) {
      await latest.create();
    }
    _output = _FlushingFileOutput(file: latest, onWriteError: onWriteError);
    await _output!.init();
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
}

class LevelFanoutOutput extends LogOutput {
  LevelFanoutOutput(this.sinks);

  final List<LogFileSink> sinks;

  @override
  void output(OutputEvent event) {
    for (final sink in sinks) {
      sink.output(event);
    }
  }

  Future<void> flush() async {
    for (final sink in sinks) {
      await sink.flush();
    }
  }

  @override
  Future<void> destroy() async {
    for (final sink in sinks) {
      await sink.destroy();
    }
  }
}

Future<List<String>> listLogFilesIn(Directory dir) async {
  if (!await dir.exists()) return [];
  final files = <File>[];
  await for (final entity in dir.list()) {
    if (entity is File && entity.path.endsWith('.log')) {
      files.add(entity);
    }
  }
  files.sort((a, b) {
    final aLatest = p.basename(a.path) == 'latest.log';
    final bLatest = p.basename(b.path) == 'latest.log';
    if (aLatest && !bLatest) return -1;
    if (!aLatest && bLatest) return 1;
    return b.lastModifiedSync().compareTo(a.lastModifiedSync());
  });
  return files.map((f) => f.path).toList();
}

/// Append-only file output that buffers lines and writes them off the caller's
/// isolate.
///
/// High-volume diagnostics (ACP frame mirroring emits several lines per model
/// token) must not do a synchronous write-with-flush on the UI isolate: at tens
/// of lines per second the fsyncs starve the frame loop. Lines are batched for
/// [_flushDelay] and written asynchronously; [flush] forces a write (tests, log
/// viewer, rotation, shutdown).
class _FlushingFileOutput extends LogOutput {
  _FlushingFileOutput({required this.file, this.onWriteError});

  final File file;

  /// Called when an asynchronous write fails (the logger disables file
  /// logging on storage errors).
  final void Function(Object error)? onWriteError;

  static const Duration _flushDelay = Duration(milliseconds: 200);

  final StringBuffer _buffer = StringBuffer();
  Timer? _flushTimer;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<void> init() async {}

  @override
  void output(OutputEvent event) {
    if (event.lines.isEmpty) return;
    for (final line in event.lines) {
      _buffer.writeln(line);
    }
    _flushTimer ??= Timer(_flushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final text = _buffer.toString();
    _buffer.clear();
    if (text.isEmpty) return _pendingWrite;
    _pendingWrite = _pendingWrite.then((_) => _append(text));
    return _pendingWrite;
  }

  Future<void> _append(String text) async {
    try {
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } on Object catch (error) {
      onWriteError?.call(error);
    }
  }

  @override
  Future<void> destroy() => flush();
}
