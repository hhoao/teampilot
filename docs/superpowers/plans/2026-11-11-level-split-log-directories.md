# 按级别分目录的文件日志 + latest.log 滚动 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `AppLogger` 文本日志按 error/warn/info/debug 四个目录级联写入，每个目录当前文件固定为 `latest.log`，查看器按目录切级别。

**Architecture:** 单个 `AppLogger` + 单个带 `_FileLogFilter` 的 `Logger`，输出换成扇出 `LogOutput`。每个启用中的级别目录一个 `LogFileSink`（内部仍是 `_FlushingFileOutput`），按 `event.level.value >= sink.minLevel.value` 写入该目录的 `latest.log`。查看器级别下拉只换 `listLogFiles(level:)` 的目录，不再按行过滤级别。

**Tech Stack:** Flutter / Dart、`package:logger` 2.8、`path`。

## Global Constraints

- 永远不要直接运行 `flutter test`；测试统一用 `cd client && dart run tool/run_tests.dart <paths>`。
- 内层循环：`flutter analyze --no-fatal-infos --no-fatal-warnings` + 单个测试文件；不要在每个步骤跑全量。
- 诊断用 `AppLogger`，禁止 `print`。
- 未经用户明确要求，不要创建 git commit；每个任务末尾只做检查点。
- 不改任何 `AppLogger.d/i/w/e` 调用方，不改 `ErrorLogService` / `logs/errors.jsonl`。
- `logger_utils.dart` 已约 737 行：把文件 IO 抽到 `log_file_sink.dart`，不要继续把扇出/滚动塞进同一个文件。

## File structure

| File | Responsibility |
|------|----------------|
| `client/lib/utils/logging/app_log_level.dart` | `AppLogLevel`、目录名、查看器 label 映射 |
| `client/lib/utils/logging/log_file_sink.dart` | 每目录 `latest.log`、扇出、滚动、列举、归档清理；搬入现有 `_FlushingFileOutput` |
| `client/lib/utils/logging/logger_utils.dart` | `AppLogger` 控制台 + pending + 把事件交给扇出 |
| `client/lib/pages/system/log_viewer_filter.dart` | 级别下拉列表；`filterLogLines` 不再按级别砍行 |
| `client/lib/pages/system/log_viewer_panel.dart` | 切级别时按目录重新 `listLogFiles` |
| `client/lib/pages/system/log_viewer_toolbar.dart` | release 隐藏 DEBUG |
| `client/lib/utils/logging/app_error_utils.dart` | 识别新日志路径为存储错误 |
| `docs/workspace-storage-layout.md` / `docs/DEBUGGING.md` / `docs/PERFORMANCE_ANALYSIS.md` | 新路径 |

---

### Task 1: 级联写入 `logs/{level}/latest.log`

**Files:**
- Create: `client/lib/utils/logging/app_log_level.dart`
- Create: `client/lib/utils/logging/log_file_sink.dart`
- Modify: `client/lib/utils/logging/logger_utils.dart`
- Test: `client/test/utils/logging/logger_utils_test.dart`

**Interfaces:**
- Consumes: 现有 `AppLogger.initFileLogging` / `d/i/w/e` / `flushFileLogging`。
- Produces:
  - `AppLogLevel.directoryName` → `debug` / `info` / `warn` / `error`
  - `appLogLevelFromViewerLabel(String label)` → `AppLogLevel?`（`ALL` 和未知 → `null`）
  - `fullTimelineLogLevel({required bool includeDebug})` → `AppLogLevel`
  - `AppLogger.listLogFiles({String? appDataRoot, AppLogLevel? level})` → `Future<List<String>>`
  - `AppLogger.currentLogFilePath` → 完整时间线目录的 `latest.log`
  - `AppLogger.resetForTest()` → `Future<void>`
  - `AppLogger.clock` → `DateTime Function()`，默认 `DateTime.now`
  - `AppLogger.maxLogFileSize` → `int`，默认 `5 * 1024 * 1024`
  - `AppLogger.writeDebugFilesForTest` → `bool?`，`null` 表示跟 `kDebugMode`
  - `LogFileSink`（`log_file_sink.dart`）：`directoryName`、`minLevel`、`latestFile`、`init`、`output`、`flush`、`destroy`、`rotateIfNeeded`

- [ ] **Step 1: 写失败的测试**

把 `client/test/utils/logging/logger_utils_test.dart` 整文件换成：

```dart
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
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run:

```bash
cd client && dart run tool/run_tests.dart test/utils/logging/logger_utils_test.dart
```

Expected: 编译失败（没有 `resetForTest` / `directoryName` / `writeDebugFilesForTest`）或断言失败（仍然写 `logs/app_*.log`）。

- [ ] **Step 3: 抽出 sink + 接到 AppLogger**

先建 `client/lib/utils/logging/app_log_level.dart`（完整内容在本步骤末尾）：把 `logger_utils.dart` 里的 `enum AppLogLevel` 挪过去，`logger_utils.dart` 改为 `export 'app_log_level.dart';`。这样 `log_file_sink.dart` 只 import `app_log_level.dart`，避免和 `AppLogger` 循环引用。

新建 `client/lib/utils/logging/log_file_sink.dart`。把 `logger_utils.dart` 里的 `_FlushingFileOutput`（原 669–719 行）原样搬进这个文件并保持私有。同一文件再加入：

```dart
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

  Directory get directory =>
      Directory(p.join(logsRoot, level.directoryName));

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

  /// `true` = 已滚动或无需滚动；`false` = 改名失败，已恢复写入当前 `latest.log`。
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
            'app_$y-$mo-$d_${clock().millisecondsSinceEpoch}.log',
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
    _output = _FlushingFileOutput(
      file: latestFile,
      onWriteError: onWriteError,
    );
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
```

`_FlushingFileOutput` 已有 `final File file`，sink 用 `_output?.file` 即可。改名失败不要在 sink 里打 console：`rotate()` 返回 `false`，由 `AppLogger` 打 warn。

改 `AppLogger` 字段：

```dart
  static const int _maxLogFiles = 5;
  static const int _maxLogAgeDays = 7;

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  @visibleForTesting
  int maxLogFileSize = 5 * 1024 * 1024;

  @visibleForTesting
  bool? writeDebugFilesForTest;

  Logger? _consoleLogger;
  Logger? _fileLogger;
  LevelFanoutOutput? _fanout;
  List<LogFileSink> _sinks = [];
  String? _logDirPath;
```

删掉 `_fileLogOutput`、`_logFile`。`initFileLogging` 在创建 `logs/` 之后：

```dart
      _logDirPath = logDir.path;
      await _cleanOldLogs(logDir);

      final includeDebug = writeDebugFilesForTest ?? kDebugMode;
      final levels = <AppLogLevel>[
        if (includeDebug) AppLogLevel.debug,
        AppLogLevel.info,
        AppLogLevel.warning,
        AppLogLevel.error,
      ];
      _sinks = [
        for (final level in levels)
          LogFileSink(
            logsRoot: logDir.path,
            level: level,
            clock: () => clock(),
            maxLogFileSize: maxLogFileSize,
            onWriteError: _handleFileWriteError,
          ),
      ];
      for (final sink in _sinks) {
        await sink.init();
      }
      _fanout = LevelFanoutOutput(_sinks);
      _fileLogger = Logger(
        printer: _printer(colors: false),
        output: _fanout!,
        filter: _FileLogFilter(),
      );
```

`_writeToFile` 里 `_maybeRotate()` 保留调用。`flushFileLogging` 改为 `await _fanout?.flush();`。

```dart
  String? get currentLogFilePath {
    final includeDebug = writeDebugFilesForTest ?? kDebugMode;
    final wanted = fullTimelineLogLevel(includeDebug: includeDebug);
    for (final sink in _sinks) {
      if (sink.level == wanted) return sink.latestFile.path;
    }
    return _sinks.isEmpty ? null : _sinks.first.latestFile.path;
  }

  Future<List<String>> listLogFiles({
    String? appDataRoot,
    AppLogLevel? level,
  }) async {
    final dirPath =
        _logDirPath ??
        (appDataRoot != null ? p.join(appDataRoot, 'logs') : null);
    if (dirPath == null) return [];
    final includeDebug = writeDebugFilesForTest ?? kDebugMode;
    final resolved = level ?? fullTimelineLogLevel(includeDebug: includeDebug);
    return listLogFilesIn(Directory(p.join(dirPath, resolved.directoryName)));
  }

  @visibleForTesting
  Future<void> resetForTest() async {
    _fileLoggingDisabled = false;
    _fileLoggerInitialized = false;
    _fileLoggerInitializing = false;
    _pendingFileLogs.clear();
    _fileLogger = null;
    _consoleLogger = null;
    _logDirPath = null;
    _lastRotateCheck = null;
    clock = DateTime.now;
    maxLogFileSize = 5 * 1024 * 1024;
    writeDebugFilesForTest = null;
    final fanout = _fanout;
    _fanout = null;
    _sinks = [];
    if (fanout != null) {
      await fanout.destroy();
    }
  }
```

`_rotateIfNeeded` 先改成遍历 `_sinks` 调 `rotateIfNeeded()`（Task 2 会补日期/大小细节；Task 1 里 `LogFileSink.rotateIfNeeded` 已经按大小和日期判断，可以一并接上，但本任务测试不覆盖滚动）。`_disableFileLogging` 里 destroy `_fanout` 而不是 `_fileLogOutput`。

`getLogFiles` 把 `level` 传下去：

```dart
  Future<List<String>> getLogFiles({
    String? appDataRoot,
    AppLogLevel? level,
  }) => listLogFiles(appDataRoot: appDataRoot, level: level);
```

`logger_utils.dart` 顶部 `import 'log_file_sink.dart';` 和 `export 'app_log_level.dart';`。`app_log_level.dart` 全文：

`app_log_level.dart`：

```dart
import 'package:logger/logger.dart';

enum AppLogLevel { debug, info, warning, error }

extension AppLogLevelX on AppLogLevel {
  String get directoryName => switch (this) {
    AppLogLevel.debug => 'debug',
    AppLogLevel.info => 'info',
    AppLogLevel.warning => 'warn',
    AppLogLevel.error => 'error',
  };

  Level toLoggerLevel() => switch (this) {
    AppLogLevel.debug => Level.debug,
    AppLogLevel.info => Level.info,
    AppLogLevel.warning => Level.warning,
    AppLogLevel.error => Level.error,
  };
}

AppLogLevel? appLogLevelFromViewerLabel(String label) {
  return switch (label) {
    'DEBUG' => AppLogLevel.debug,
    'INFO' => AppLogLevel.info,
    'WARNING' => AppLogLevel.warning,
    'ERROR' => AppLogLevel.error,
    _ => null,
  };
}

AppLogLevel fullTimelineLogLevel({required bool includeDebug}) =>
    includeDebug ? AppLogLevel.debug : AppLogLevel.info;
```

`logger.dart` 继续 `export 'logger_utils.dart' show AppLogger;`，测试已经 import `logger_utils.dart`，能拿到 `AppLogLevel`。

- [ ] **Step 4: 跑测试，确认通过**

Run:

```bash
cd client && dart run tool/run_tests.dart test/utils/logging/logger_utils_test.dart
```

Expected: PASS（4 tests）。

然后：

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: 无 error。若 `logger_utils.dart` 里还有对 `_logFile` / `_fileLogOutput` 的引用，删掉或改成 `_fanout` / `currentLogFilePath`。

- [ ] **Step 5: 检查点**

确认 `logs/errors.jsonl` 路径代码未改。不要 commit。

---

### Task 2: latest.log 按大小/按天滚动 + 按目录保留

**Files:**
- Modify: `client/lib/utils/logging/log_file_sink.dart`
- Modify: `client/lib/utils/logging/logger_utils.dart`（`_cleanOldLogs`、`checkRotationForTest`）
- Test: `client/test/utils/logging/logger_utils_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `LogFileSink.rotate` / `rotateIfNeeded`、`AppLogger.clock`、`AppLogger.maxLogFileSize`。
- Produces:
  - `AppLogger.checkRotationForTest()` → `Future<void>`（绕过 5 秒节流，对每个 sink 调 `rotateIfNeeded`）
  - `_cleanOldLogs`：每个级别目录独立保留 `latest.log` + 最多 5 个且不超过 7 天的 `app_*.log`；根上遗留 `app_*.log` 只按 7 天删；永不删 `errors.jsonl`

- [ ] **Step 1: 写失败的测试**

在 `logger_utils_test.dart` 的 `main()` 末尾追加：

```dart
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
```

- [ ] **Step 2: 跑测试，确认失败**

Run:

```bash
cd client && dart run tool/run_tests.dart test/utils/logging/logger_utils_test.dart --plain-name "size rotation"
```

Expected: 失败（没有 `checkRotationForTest`，或大小滚动未归档）。

- [ ] **Step 3: 实现滚动与清理**

在 `AppLogger` 上：

```dart
  @visibleForTesting
  Future<void> checkRotationForTest() async {
    _lastRotateCheck = null;
    await _rotateIfNeeded();
  }

  Future<void> _rotateIfNeeded() async {
    if (_fileLoggingDisabled) return;
    for (final sink in _sinks) {
      final ok = await sink.rotateIfNeeded();
      if (!ok) {
        _consoleLogger?.w(
          '[AppLogger] failed to archive ${sink.latestFile.path}; keeping latest.log',
        );
      }
    }
  }
```

把 `_maybeRotate` 继续 5 秒节流后 `unawaited(_rotateIfNeeded())`。

重写 `_cleanOldLogs`：

```dart
  Future<void> _cleanOldLogs(Directory logDir) async {
    try {
      final includeDebug = writeDebugFilesForTest ?? kDebugMode;
      final dirs = <Directory>[
        for (final level in [
          if (includeDebug) AppLogLevel.debug,
          AppLogLevel.info,
          AppLogLevel.warning,
          AppLogLevel.error,
        ])
          Directory(p.join(logDir.path, level.directoryName)),
      ];
      for (final dir in dirs) {
        await _cleanDirectory(dir, dropByAgeAndCount: true);
      }
      await _cleanDirectory(logDir, dropByAgeAndCount: false, recursive: false);
    } on Object catch (e) {
      _consoleLogger?.w('[AppLogger] failed to clean old logs: $e');
    }
  }

  Future<void> _cleanDirectory(
    Directory dir, {
    required bool dropByAgeAndCount,
    bool recursive = true,
  }) async {
    if (!await dir.exists()) return;
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == 'latest.log' || name == 'errors.jsonl') continue;
      if (!name.endsWith('.log')) continue;
      files.add(entity);
    }
    files.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    final now = clock();
    var kept = 0;
    for (final file in files) {
      final age = now.difference(file.lastModifiedSync()).inDays;
      final dropAge = age > _maxLogAgeDays;
      final dropCount = dropByAgeAndCount && kept >= _maxLogFiles;
      if (dropAge || dropCount) {
        await file.delete();
      } else {
        kept++;
      }
    }
  }
```

根目录调用 `dropByAgeAndCount: false`，所以遗留 `logs/app_*.log` 只按 7 天删，不占用某个级别的 5 个配额。`latest.log` 和 `errors.jsonl` 跳过。

- [ ] **Step 4: 跑测试，确认通过**

Run:

```bash
cd client && dart run tool/run_tests.dart test/utils/logging/logger_utils_test.dart
```

Expected: PASS（7 tests）。若 Windows 上 `rename` 在 destroy 之后仍失败，确认 `rotate()` 先 `await current.destroy()` 再 `rename`。

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 5: 检查点**

不要 commit。

---

### Task 3: 日志路径算存储错误

**Files:**
- Modify: `client/lib/utils/logging/app_error_utils.dart`
- Test: `client/test/utils/logging/app_error_utils_test.dart`

**Interfaces:**
- Consumes: `AppErrorUtils.classify` / `_isStorageError`。
- Produces: 含 `/logs/error/`、`/logs/warn/`、`/logs/info/`、`/logs/debug/`、`/logs/latest.log` 的错误字符串被识别为 storage。

- [ ] **Step 1: 写失败的测试**

在 `app_error_utils_test.dart` 的 `group('AppErrorUtils.classify')` 里追加：

```dart
    test('log path IO failures are storage errors', () {
      for (final path in [
        '/logs/error/latest.log',
        '/logs/warn/app_2026-11-11.log',
        '/logs/info/latest.log',
        '/logs/debug/latest.log',
        '/logs/latest.log',
        '/logs/errors.jsonl',
      ]) {
        final decision = AppErrorUtils.classify(
          FileSystemException('cannot open file', path),
        );
        expect(decision.kind, AppErrorKind.storage, reason: path);
        expect(decision.shouldReport, isFalse, reason: path);
      }
    });
```

- [ ] **Step 2: 跑测试，确认失败**

Run:

```bash
cd client && dart run tool/run_tests.dart test/utils/logging/app_error_utils_test.dart --plain-name "log path"
```

Expected: FAIL（`/logs/error/` 仍被当成 unexpected，`shouldReport: true`）。`/logs/errors.jsonl` 现有匹配可能已经 PASS。

- [ ] **Step 3: 扩匹配**

把 `_isStorageError` 末尾的

```dart
        raw.contains('/logs/app_') ||
        raw.contains('/logs/errors');
```

换成：

```dart
        raw.contains('/logs/app_') ||
        raw.contains('/logs/errors') ||
        raw.contains('/logs/error/') ||
        raw.contains('/logs/warn/') ||
        raw.contains('/logs/info/') ||
        raw.contains('/logs/debug/') ||
        raw.contains('/logs/latest.log');
```

- [ ] **Step 4: 跑测试，确认通过**

Run:

```bash
cd client && dart run tool/run_tests.dart test/utils/logging/app_error_utils_test.dart
```

Expected: PASS。

- [ ] **Step 5: 检查点**

不要 commit。

---

### Task 4: 查看器按目录切级别

**Files:**
- Modify: `client/lib/pages/system/log_viewer_filter.dart`
- Modify: `client/lib/pages/system/log_viewer_panel.dart`
- Modify: `client/lib/pages/system/log_viewer_toolbar.dart`
- Test: `client/test/pages/system/log_viewer_test.dart`
- Test: `client/test/pages/system/log_viewer_filter_test.dart`（新建）

**Interfaces:**
- Consumes: `appLogLevelFromViewerLabel`、`AppLogger.listLogFiles(level:)`、`kDebugMode`。
- Produces:
  - `logViewerLevels({required bool includeDebug})` → `List<String>`
  - `filterLogLines` 不再接收/使用 `selectedLevel`
  - `LogViewerPanel.onLevelChanged` 重新 `_loadLogFiles()`
  - `LogViewerToolbar` 用 `logViewerLevels(includeDebug: kDebugMode)`

- [ ] **Step 1: 写失败的测试**

新建 `client/test/pages/system/log_viewer_filter_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/system/log_viewer_filter.dart';

void main() {
  test('filterLogLines does not drop other levels', () {
    final lines = [
      '2026-11-11 00:00:00.000 |  INFO 1 | a.dart:1:1 | hello',
      '2026-11-11 00:00:00.000 | ERROR 1 | a.dart:1:1 | boom',
    ];
    expect(
      filterLogLines(
        rawLines: lines,
        compactView: false,
        searchText: '',
      ),
      lines,
    );
  });

  test('logViewerLevels hides DEBUG when includeDebug is false', () {
    expect(logViewerLevels(includeDebug: true), [
      'ALL',
      'DEBUG',
      'INFO',
      'WARNING',
      'ERROR',
    ]);
    expect(logViewerLevels(includeDebug: false), [
      'ALL',
      'INFO',
      'WARNING',
      'ERROR',
    ]);
  });
}
```

在 `log_viewer_test.dart` 增加 import 和 panel 测试（文件顶部已有的 toolbar 测试保留）。追加：

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:teampilot/pages/system/log_viewer_panel.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/utils/logging/logger_utils.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../support/post_frame_test_harness.dart';
```

在 `main()` 末尾：

```dart
  testWidgets('level dropdown lists files from that directory', (tester) async {
    setUpTestAppStorage();
    addTearDown(() async {
      await AppLogger.instance.resetForTest();
      tearDownTestAppStorage();
    });

    final root = AppPathsBootstrapper.current.basePath;
    await AppLogger.instance.initFileLogging(root);
    AppLogger.instance.i('info only line');
    AppLogger.instance.e('error only line', recordError: false);
    await AppLogger.instance.flushFileLogging();
    await File(p.join(root, 'logs', 'errors.jsonl')).writeAsString('{}\n');

    await tester.pumpWidget(_host(const LogViewerPanel(useSurfaceCard: false)));
    await tester.pumpAndSettle();

    final fileSelect = tester.widget<TpSelect<String>>(
      find.byKey(const Key('log-viewer-file')),
    );
    expect(
      fileSelect.items.every((path) => !path.endsWith('errors.jsonl')),
      isTrue,
    );
    expect(p.basename(fileSelect.initialItem ?? ''), 'latest.log');

    tester
        .widget<TpSelect<String>>(find.byKey(const Key('log-viewer-level')))
        .onChanged
        ?.call('ERROR');
    await tester.pumpAndSettle();

    final errorSelect = tester.widget<TpSelect<String>>(
      find.byKey(const Key('log-viewer-file')),
    );
    expect(
      errorSelect.items.every(
        (path) => path.contains('${p.separator}error${p.separator}'),
      ),
      isTrue,
    );
    expect(p.basename(errorSelect.initialItem ?? ''), 'latest.log');

    tester
        .widget<TpSelect<String>>(find.byKey(const Key('log-viewer-level')))
        .onChanged
        ?.call('INFO');
    await tester.pumpAndSettle();

    final infoSelect = tester.widget<TpSelect<String>>(
      find.byKey(const Key('log-viewer-file')),
    );
    expect(
      infoSelect.items.every(
        (path) => path.contains('${p.separator}info${p.separator}'),
      ),
      isTrue,
    );
  });
```

若 `_host` 不足以提供 `AppSettingsRepository?`，`LogViewerPanel` 已用 `context.read<AppSettingsRepository?>()`，缺 provider 时为 null，测试可以不包 Bloc。`setUpTestAppStorage` 必须在 `pumpWidget` 前调用。`setUpTestAppStorage` / `tearDownTestAppStorage` 已在 `client/test/support/post_frame_test_harness.dart`。`LogViewerPanel` 用 `context.read<AppSettingsRepository?>()`，缺 provider 时为 null，不必包 Bloc。

- [ ] **Step 2: 跑测试，确认失败**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/system/log_viewer_filter_test.dart test/pages/system/log_viewer_test.dart
```

Expected: 编译失败（`filterLogLines` 仍要 `selectedLevel`，没有 `logViewerLevels`）。

- [ ] **Step 3: 改 filter / toolbar / panel**

`log_viewer_filter.dart` 换成：

```dart
import 'package:flutter/foundation.dart';

import 'log_helpers.dart';

List<String> filterLogLines({
  required List<String> rawLines,
  required bool compactView,
  required String searchText,
}) {
  var filtered = List<String>.from(rawLines);
  if (compactView) {
    filtered = filtered.where((l) => !isLogDecorationLine(l)).toList();
  }
  if (searchText.isNotEmpty) {
    final q = searchText.toLowerCase();
    filtered = filtered.where((l) => l.toLowerCase().contains(q)).toList();
  }
  return filtered;
}

List<String> logViewerLevels({required bool includeDebug}) {
  return [
    'ALL',
    if (includeDebug) 'DEBUG',
    'INFO',
    'WARNING',
    'ERROR',
  ];
}

List<String> kLogViewerLevels = logViewerLevels(includeDebug: kDebugMode);
```

可以删掉 `logLineMatchesLevel`（确认无其它引用）。

`log_viewer_panel.dart` 的 `_filteredLines`：

```dart
    return filterLogLines(
      rawLines: _rawLines,
      compactView: _compactView,
      searchText: _searchText,
    );
```

`_loadLogFiles` 里：

```dart
      final files = await AppLogger.instance.getLogFiles(
        appDataRoot: root,
        level: appLogLevelFromViewerLabel(_selectedLevel),
      );
```

`onLevelChanged`：

```dart
            onLevelChanged: (level) {
              setState(() => _selectedLevel = level);
              unawaited(_loadLogFiles());
            },
```

需要 `import '../../utils/logging/logger_utils.dart';` 已存在。

`log_viewer_toolbar.dart`：文件下拉的 `_dropdown` 加上 `key: const Key('log-viewer-file')`，级别下拉加上 `key: const Key('log-viewer-level')`。把 `_dropdown` 增加可选 `Key? key` 并传到内部 `TpSelect`（替换现在的 `key: ValueKey<T>(value)`，改成 `key: key ?? ValueKey<T>(value)`）。级别 `items:` 换成 `logViewerLevels(includeDebug: kDebugMode)`。release 默认 `_selectedLevel = 'ALL'`，items 不含 DEBUG 时不会选中缺失项。

- [ ] **Step 4: 跑测试，确认通过**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/system/log_viewer_filter_test.dart test/pages/system/log_viewer_test.dart test/utils/logging/logger_utils_test.dart
```

Expected: PASS。

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 5: 检查点**

不要 commit。

---

### Task 5: 文档路径

**Files:**
- Modify: `docs/workspace-storage-layout.md`
- Modify: `docs/DEBUGGING.md`
- Modify: `docs/PERFORMANCE_ANALYSIS.md`

**Interfaces:**
- Consumes: spec 布局。
- Produces: 文档中的 `logs/` 描述与 `tail` 路径与实现一致。

- [ ] **Step 1: 改 storage layout**

在 `docs/workspace-storage-layout.md` 的 top-level 列表里、`session-protocol.json` 那一行后面插入：

```
  logs/
    errors.jsonl                 # ErrorLogService structured errors
    error/latest.log             # AppLogger error lines
    warn/latest.log              # warn + error
    info/latest.log              # info + warn + error
    debug/latest.log             # full timeline (debug builds only)
```

- [ ] **Step 2: 改 DEBUGGING.md**

把 ACP frame 那句末尾 `{appDataRoot}/logs/` 改成 `{appDataRoot}/logs/{level}/latest.log`（级联进对应级别目录）。

- [ ] **Step 3: 改 PERFORMANCE_ANALYSIS.md**

把

```bash
   log_dir="${XDG_DATA_HOME:-$HOME/.local/share}/com.hhoa.teampilot/logs"
   mkdir -p "$log_dir"
   log_file="$log_dir/app_$(date +%F).log"
   touch "$log_file"
   tail -n 0 -F "$log_file" \
```

换成：

```bash
   log_dir="${XDG_DATA_HOME:-$HOME/.local/share}/com.hhoa.teampilot/logs/info"
   mkdir -p "$log_dir"
   log_file="$log_dir/latest.log"
   touch "$log_file"
   tail -n 0 -F "$log_file" \
```

在该代码块下加一句：查 DEBUG 用 `logs/debug/latest.log`（仅 debug 构建）。

- [ ] **Step 4: 内层分析 + 相关测试**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/utils/logging/logger_utils_test.dart test/utils/logging/app_error_utils_test.dart test/pages/system/log_viewer_filter_test.dart test/pages/system/log_viewer_test.dart
```

Expected: analyze 干净，上述测试 PASS。

- [ ] **Step 5: 检查点**

不要 commit。实现全部通过后，等用户明确要求再提交。

---

## Spec coverage

| Spec 条目 | Task |
|-----------|------|
| 四个目录 + 级联写入 | 1 |
| `latest.log` 当前文件 | 1 |
| release 不建 `debug/` | 1 |
| `listLogFiles(level:)` 只列一个目录，`latest.log` 置顶 | 1 |
| `currentLogFilePath` 完整时间线 | 1 |
| `errors.jsonl` 不动、不出现在列表 | 1 + 4 |
| 5MB / 跨日滚动，归档名用打开日 | 2 |
| 改名失败继续写 `latest.log` | 2（实现） |
| 每目录 5 个归档 + 7 天；不删 latest / errors.jsonl | 2 |
| 根上旧 `app_*.log` 只按 7 天清 | 2 |
| 日志路径识别 | 3 |
| 查看器切目录、不再按行过滤、隐藏 DEBUG | 4 |
| 三份文档 | 5 |
| 不改 `d/i/w/e` 调用方、控制台、ACP 开关 | 全任务均不碰 |
