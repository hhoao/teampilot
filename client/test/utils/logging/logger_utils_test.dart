import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/utils/logging/logger_utils.dart';

Future<String> _readLogWhenContains(String path, String needle) async {
  final file = File(path);
  for (var attempt = 0; attempt < 40; attempt++) {
    if (await file.exists()) {
      final contents = await file.readAsString();
      if (contents.contains(needle)) return contents;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!await file.exists()) return '';
  return file.readAsString();
}

File _latest(Directory root, AppLogLevel level) =>
    File(p.join(root.path, 'logs', level.directoryName, 'latest.log'));

void main() {
  late Directory temp;

  setUp(() async {
    await AppLogger.instance.resetForTest();
    temp = await Directory.systemTemp.createTemp('tp_logs_');
  });

  tearDown(() async {
    await AppLogger.instance.resetForTest();
    try {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    } on Object {
      // Log file may still be open on Windows.
    }
  });

  test('initFileLogging writes cascade latest.log files', () async {
    await AppLogger.instance.initFileLogging(temp.path);
    AppLogger.instance.i('hello from test');
    AppLogger.instance.d('trace from test');
    await AppLogger.instance.flushFileLogging();

    final debugPath = _latest(temp, AppLogLevel.debug).path;
    expect(AppLogger.instance.currentLogFilePath, debugPath);

    final debugContents = await _readLogWhenContains(debugPath, 'hello from test');
    expect(debugContents, contains('hello from test'));
    expect(debugContents, contains('trace from test'));
    expect(
      debugContents,
      matches(
        RegExp(
          r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \|  INFO \d+ \| [^\|]+\.dart:\d+:\d+ \| hello from test',
        ),
      ),
    );

    final infoContents = await File(
      _latest(temp, AppLogLevel.info).path,
    ).readAsString();
    expect(infoContents, contains('hello from test'));
    expect(infoContents, isNot(contains('trace from test')));

    expect(await _latest(temp, AppLogLevel.warning).exists(), isTrue);
    expect(await _latest(temp, AppLogLevel.error).exists(), isTrue);
    expect(
      await File(_latest(temp, AppLogLevel.warning).path).readAsString(),
      isNot(contains('hello from test')),
    );
    expect(
      await File(_latest(temp, AppLogLevel.error).path).readAsString(),
      isNot(contains('hello from test')),
    );

    for (var i = 0; i < 200; i++) {
      AppLogger.instance.i('burst line $i');
    }
    await AppLogger.instance.flushFileLogging();

    final afterBurst = await File(debugPath).readAsString();
    expect(afterBurst, contains('burst line 0\n'));
    expect(afterBurst, contains('burst line 199'));
    expect(
      afterBurst.indexOf('burst line 0\n'),
      lessThan(afterBurst.indexOf('burst line 199')),
    );
  });

  test('error lines cascade into every enabled latest.log', () async {
    await AppLogger.instance.initFileLogging(temp.path);
    AppLogger.instance.e('boom from test', recordError: false);
    await AppLogger.instance.flushFileLogging();

    for (final level in [
      AppLogLevel.debug,
      AppLogLevel.info,
      AppLogLevel.warning,
      AppLogLevel.error,
    ]) {
      expect(
        await File(_latest(temp, level).path).readAsString(),
        contains('boom from test'),
      );
    }
  });

  test('listLogFiles lists one directory and puts latest.log first', () async {
    await AppLogger.instance.initFileLogging(temp.path);
    AppLogger.instance.e('listed', recordError: false);
    await AppLogger.instance.flushFileLogging();

    final errorFiles = await AppLogger.instance.listLogFiles(
      level: AppLogLevel.error,
    );
    expect(errorFiles, isNotEmpty);
    expect(p.basename(errorFiles.first), 'latest.log');
    expect(
      errorFiles.every((path) => path.contains('${p.separator}error${p.separator}')),
      isTrue,
    );

    final allFiles = await AppLogger.instance.listLogFiles();
    expect(p.basename(allFiles.first), 'latest.log');
    expect(allFiles.first, AppLogger.instance.currentLogFilePath);
    expect(
      allFiles.any((path) => path.contains('${p.separator}error${p.separator}')),
      isFalse,
    );
  });

  test('release-style init skips the debug directory', () async {
    AppLogger.instance.writeDebugFilesForTest = false;
    await AppLogger.instance.initFileLogging(temp.path);
    AppLogger.instance.i('no debug dir');
    await AppLogger.instance.flushFileLogging();

    expect(await Directory(p.join(temp.path, 'logs', 'debug')).exists(), isFalse);
    expect(await _latest(temp, AppLogLevel.info).exists(), isTrue);
    expect(
      AppLogger.instance.currentLogFilePath,
      _latest(temp, AppLogLevel.info).path,
    );
  });

  test('size rotation archives latest.log and keeps writing to a new one', () async {
    AppLogger.instance.maxLogFileSize = 200;
    await AppLogger.instance.initFileLogging(temp.path);
    AppLogger.instance.e('x' * 300, recordError: false);
    await AppLogger.instance.flushFileLogging();
    await AppLogger.instance.checkRotationForTest();
    AppLogger.instance.e('after-rotate', recordError: false);
    await AppLogger.instance.flushFileLogging();

    final errorDir = Directory(p.join(temp.path, 'logs', 'error'));
    final names = errorDir
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList();
    expect(names, contains('latest.log'));
    expect(names.any((n) => n.startsWith('app_') && n.endsWith('.log')), isTrue);
    expect(
      await File(p.join(errorDir.path, 'latest.log')).readAsString(),
      contains('after-rotate'),
    );
    final archive = errorDir
        .listSync()
        .whereType<File>()
        .firstWhere((f) => p.basename(f.path).startsWith('app_'));
    expect(await archive.readAsString(), contains('x' * 300));
    expect(await archive.readAsString(), isNot(contains('after-rotate')));
  });

  test('day rotation names the archive with the opened date', () async {
    var now = DateTime(2026, 11, 10, 23, 0);
    AppLogger.instance.clock = () => now;
    await AppLogger.instance.initFileLogging(temp.path);
    AppLogger.instance.w('yesterday line');
    await AppLogger.instance.flushFileLogging();

    now = DateTime(2026, 11, 11, 0, 30);
    await AppLogger.instance.checkRotationForTest();
    AppLogger.instance.w('today line');
    await AppLogger.instance.flushFileLogging();

    final warnDir = Directory(p.join(temp.path, 'logs', 'warn'));
    final archive = File(p.join(warnDir.path, 'app_2026-11-10.log'));
    expect(await archive.exists(), isTrue);
    expect(await archive.readAsString(), contains('yesterday line'));
    expect(
      await File(p.join(warnDir.path, 'latest.log')).readAsString(),
      contains('today line'),
    );
  });

  test('clearOldLogs keeps latest.log and drops stale archives per directory', () async {
    await AppLogger.instance.initFileLogging(temp.path);
    final errorDir = Directory(p.join(temp.path, 'logs', 'error'));
    final stale = File(p.join(errorDir.path, 'app_2026-01-01.log'));
    await stale.writeAsString('old\n');
    await stale.setLastModified(DateTime.now().subtract(const Duration(days: 8)));

    for (var i = 0; i < 6; i++) {
      final extra = File(p.join(errorDir.path, 'app_2026-11-0$i.log'));
      await extra.writeAsString('keep-candidate $i\n');
      await extra.setLastModified(
        DateTime.now().subtract(Duration(hours: i + 1)),
      );
    }

    final leftover = File(p.join(temp.path, 'logs', 'app_2026-01-02.log'));
    await leftover.writeAsString('root leftover\n');
    await leftover.setLastModified(
      DateTime.now().subtract(const Duration(days: 8)),
    );
    final errorsJsonl = File(p.join(temp.path, 'logs', 'errors.jsonl'));
    await errorsJsonl.writeAsString('{"keep":true}\n');

    await AppLogger.instance.clearOldLogs();

    expect(await File(p.join(errorDir.path, 'latest.log')).exists(), isTrue);
    expect(await stale.exists(), isFalse);
    expect(await leftover.exists(), isFalse);
    expect(await errorsJsonl.exists(), isTrue);
    final archives = errorDir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('app_'))
        .toList();
    expect(archives.length, lessThanOrEqualTo(5));
  });
}
