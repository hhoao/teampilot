import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'process_table_parser.dart';
import 'resource_memory_models.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';

/// Host process sweep → [ResourceMemorySnapshot] for the Resource Manager.
///
/// Concurrent [collect] calls coalesce onto one in-flight sweep. Failures
/// never throw to callers; last-good or empty snapshot is returned instead.
class ProcessMetricsService {
  ProcessMetricsService({
    Future<String> Function()? readProcessTable,
    Future<ResourceHostMemory?> Function()? readHostMemory,
    int Function()? appPid,
    List<ProcessTableRow> Function(String text)? parseProcessTable,
    int historyCapacity = 30,
  })  : _readProcessTable = readProcessTable ?? _defaultReadProcessTable,
        _readHostMemory = readHostMemory ?? _defaultReadHostMemory,
        _appPid = appPid ?? (() => pid),
        _parseProcessTable = parseProcessTable ?? _defaultParseProcessTable,
        _historyCapacity = historyCapacity;

  /// Test seam: when set, [GlobalResourceManagerHost] uses this instead of a
  /// real process-table sweep so widget tests never spawn `ps`/`powershell`
  /// (and their `.timeout` timers). Mirrors [GitService.debugOverrideFactory].
  @visibleForTesting
  static ProcessMetricsService Function()? debugOverrideFactory;

  static const _appHistoryKey = 'app';
  static const _sweepTimeout = Duration(seconds: 5);

  /// Args for the Unix process-table sweep (`ps`).
  ///
  /// Must be a **single** `-eo` format string (Orca: `ps -eo pid=,ppid=,pcpu=,rss=`).
  /// Splitting `pid=` / `ppid=` / … into separate argv tokens makes Linux `ps`
  /// treat them as a PID list and exit 1 with empty stdout — Resource Manager
  /// then shows `—` for every CPU/Mem cell.
  static const unixPsArgs = ['-eo', 'pid=,ppid=,pcpu=,rss='];

  final Future<String> Function() _readProcessTable;
  final Future<ResourceHostMemory?> Function() _readHostMemory;
  final int Function() _appPid;
  final List<ProcessTableRow> Function(String text) _parseProcessTable;
  final int _historyCapacity;

  Future<ResourceMemorySnapshot>? _inflight;
  ResourceMemorySnapshot? _lastGood;

  final Map<String, List<int>> _historyByKey = {};
  final List<int> _totalMemoryHistory = [];

  /// Collects a coalesced host + registered-pid metrics snapshot.
  Future<ResourceMemorySnapshot> collect({
    required Map<String, int> registeredPids,
    required Map<String, String> bindingKeyToGroupKey,
  }) {
    final existing = _inflight;
    if (existing != null) return existing;

    final pending = _runCollect(
      registeredPids: registeredPids,
      bindingKeyToGroupKey: bindingKeyToGroupKey,
    );
    _inflight = pending;
    return pending.whenComplete(() {
      if (identical(_inflight, pending)) {
        _inflight = null;
      }
    });
  }

  Future<ResourceMemorySnapshot> _runCollect({
    required Map<String, int> registeredPids,
    required Map<String, String> bindingKeyToGroupKey,
  }) async {
    try {
      final tableText = await _readProcessTable();
      // Empty table on non-Android is a soft-fail (timeout / sweep unavailable).
      // Android intentionally returns '' (no local process sweep).
      if (tableText.trim().isEmpty && !Platform.isAndroid) {
        return _returnLastGoodOrEmpty(
          reason: 'empty process table (timeout or sweep unavailable)',
        );
      }

      final rows = _parseProcessTable(tableText);
      final host = await _safeHostMemory();
      final collectedAt = DateTime.now();

      final knownPids = <int>{for (final row in rows) row.pid};

      final leafMetrics = <String, ResourceLeafMetrics>{};
      final groupMemory = <String, int>{};
      // Orca claim-once: overlapping PTY subtrees must not double-count RSS/CPU.
      final claimed = <int>{};

      for (final entry in registeredPids.entries) {
        final bindingKey = entry.key;
        final leafPid = entry.value;
        if (!knownPids.contains(leafPid)) {
          leafMetrics[bindingKey] = ResourceLeafMetrics(pid: leafPid);
          continue;
        }
        final usage = subtreeUsageClaiming(rows, leafPid, claimed);
        leafMetrics[bindingKey] = ResourceLeafMetrics(
          cpu: usage.cpuPercent,
          memoryBytes: usage.memoryBytes,
          pid: leafPid,
        );
        final groupKey = bindingKeyToGroupKey[bindingKey];
        if (groupKey != null) {
          groupMemory[groupKey] =
              (groupMemory[groupKey] ?? 0) + usage.memoryBytes;
        }
      }

      ResourceAppMemory? app;
      final appPidValue = _appPid();
      if (knownPids.contains(appPidValue)) {
        // Self only — full subtree would roll every spawned PTY/agent into App
        // and then again into leaf totals (unlike Orca's Electron app metrics).
        final usage = processSelfUsage(rows, appPidValue);
        _pushHistory(_appHistoryKey, usage.memoryBytes);
        app = ResourceAppMemory(
          cpu: usage.cpuPercent,
          memoryBytes: usage.memoryBytes,
          history: List<int>.of(_historyByKey[_appHistoryKey] ?? const []),
        );
      } else {
        app = ResourceAppMemory(
          history: List<int>.of(_historyByKey[_appHistoryKey] ?? const []),
        );
      }

      for (final entry in groupMemory.entries) {
        _pushHistory(entry.key, entry.value);
      }

      // Keep prior rings for active groups even when this tick had no sample
      // (all pids missing) so sparklines do not disappear for one tick.
      final activeGroupKeys = bindingKeyToGroupKey.values.toSet();
      final groupHistory = <String, List<int>>{
        for (final key in activeGroupKeys)
          if (_historyByKey.containsKey(key))
            key: List<int>.of(_historyByKey[key]!),
      };

      double? totalCpu;
      int? totalMemory;
      final appCpu = app.cpu;
      final appMem = app.memoryBytes;
      if (appCpu != null) {
        totalCpu = (totalCpu ?? 0) + appCpu;
      }
      if (appMem != null) {
        totalMemory = (totalMemory ?? 0) + appMem;
      }
      for (final leaf in leafMetrics.values) {
        final cpu = leaf.cpu;
        final mem = leaf.memoryBytes;
        if (cpu != null) {
          totalCpu = (totalCpu ?? 0) + cpu;
        }
        if (mem != null) {
          totalMemory = (totalMemory ?? 0) + mem;
        }
      }

      if (totalMemory != null) {
        _totalMemoryHistory.add(totalMemory);
        while (_totalMemoryHistory.length > _historyCapacity) {
          _totalMemoryHistory.removeAt(0);
        }
      }

      final snapshot = ResourceMemorySnapshot(
        collectedAt: collectedAt,
        totalCpu: totalCpu,
        totalMemory: totalMemory,
        host: host,
        app: app,
        leafMetrics: leafMetrics,
        groupHistory: groupHistory,
        totalMemoryHistory: List<int>.of(_totalMemoryHistory),
      );
      _lastGood = snapshot;
      return snapshot;
    } catch (e, st) {
      AppLogger.instance.w(
        'ProcessMetricsService.collect failed; returning last-good/empty',
        error: e,
        stackTrace: st,
      );
      return _lastGood ??
          ResourceMemorySnapshot(collectedAt: DateTime.now());
    }
  }

  ResourceMemorySnapshot _returnLastGoodOrEmpty({required String reason}) {
    AppLogger.instance.w(
      'ProcessMetricsService.collect soft-fail: $reason; '
      'returning last-good/empty',
    );
    return _lastGood ?? ResourceMemorySnapshot(collectedAt: DateTime.now());
  }

  void _pushHistory(String key, int memoryBytes) {
    final ring = _historyByKey.putIfAbsent(key, () => <int>[]);
    ring.add(memoryBytes);
    while (ring.length > _historyCapacity) {
      ring.removeAt(0);
    }
  }

  Future<ResourceHostMemory?> _safeHostMemory() async {
    try {
      return await _readHostMemory();
    } catch (e, st) {
      AppLogger.instance.w(
        'ProcessMetricsService host memory failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  static List<ProcessTableRow> _defaultParseProcessTable(String text) {
    if (Platform.isWindows) {
      return parseWindowsProcessTable(text);
    }
    return parseUnixProcessTable(text);
  }

  static Future<String> _defaultReadProcessTable() async {
    if (Platform.isAndroid) {
      return '';
    }
    try {
      if (Platform.isWindows) {
        return await _readWindowsProcessTable();
      }
      final result = await Process.run(
        'ps',
        unixPsArgs,
        environment: {
          ...Platform.environment,
          'LC_ALL': 'C',
          'LANG': 'C',
        },
        stdoutEncoding: const SystemEncoding(),
      ).timeout(_sweepTimeout);
      if (result.exitCode != 0) {
        throw ProcessException(
          'ps',
          unixPsArgs,
          '${result.stderr}',
          result.exitCode,
        );
      }
      return result.stdout as String;
    } on TimeoutException {
      AppLogger.instance.w('ProcessMetricsService process table timed out');
      // Soft-fail as empty so [_runCollect] returns last-good (not a null
      // metrics “success” that overwrites the cache).
      return '';
    }
  }

  static Future<String> _readWindowsProcessTable() async {
    // Prefer PowerShell CIM; fall back to wmic.
    try {
      final result = await Process.run(
        'powershell',
        const [
          '-NoProfile',
          '-Command',
          "Get-CimInstance Win32_Process | "
              "ForEach-Object { "
              "[string]::Join([char]9, @("
              "\$_.ProcessId, \$_.ParentProcessId, \$_.WorkingSetSize"
              ')) }',
        ],
      ).timeout(_sweepTimeout);
      if (result.exitCode == 0) {
        final out = result.stdout as String;
        if (out.trim().isNotEmpty) return out;
      }
    } catch (_) {
      // Fall through to wmic.
    }

    final result = await Process.run(
      'wmic',
      const [
        'process',
        'get',
        'ProcessId,ParentProcessId,WorkingSetSize',
        '/format:csv',
      ],
    ).timeout(_sweepTimeout);
    if (result.exitCode != 0) {
      throw ProcessException(
        'wmic',
        const ['process', 'get', 'ProcessId,ParentProcessId,WorkingSetSize'],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return _wmicCsvToTabRows(result.stdout as String);
  }

  /// Converts WMIC CSV (`Node,ParentProcessId,ProcessId,WorkingSetSize`) to
  /// tab-delimited CIM-style rows expected by [parseWindowsProcessTable].
  static String _wmicCsvToTabRows(String csv) {
    final buf = StringBuffer();
    for (final raw in csv.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.toLowerCase().startsWith('node,')) continue;
      final fields = line.split(',');
      if (fields.length < 4) continue;
      final ppid = fields[1].trim();
      final pid = fields[2].trim();
      final ws = fields[3].trim();
      if (pid.isEmpty || ppid.isEmpty) continue;
      buf.writeln('$pid\t$ppid\t$ws');
    }
    return buf.toString();
  }

  static Future<ResourceHostMemory?> _defaultReadHostMemory() async {
    if (Platform.isAndroid) return null;

    final total = _readTotalMemoryBytes();
    final free = _readFreeMemoryBytes();
    if (total == null || free == null || total <= 0) return null;

    final used = (total - free).clamp(0, total);
    return ResourceHostMemory(
      totalMemory: total,
      freeMemory: free,
      usedMemory: used,
      memoryUsagePercent: (used / total) * 100,
      cpuCoreCount: Platform.numberOfProcessors,
      loadAverage1m: _readLoadAverage1m(),
    );
  }

  static int? _readTotalMemoryBytes() {
    if (Platform.isLinux) {
      final kb = _meminfoKb('MemTotal:');
      return kb == null ? null : kb * 1024;
    }
    if (Platform.isMacOS) {
      return _sysctlInt('hw.memsize');
    }
    if (Platform.isWindows) {
      // Best-effort: skip synchronous Process.run for host mem on Windows
      // when not injected; leave null rather than block.
      return null;
    }
    return null;
  }

  static int? _readFreeMemoryBytes() {
    if (Platform.isLinux) {
      // Prefer MemAvailable (reclaimable) over MemFree.
      final available = _meminfoKb('MemAvailable:');
      if (available != null) return available * 1024;
      final free = _meminfoKb('MemFree:');
      if (free != null) return free * 1024;
      return null;
    }
    if (Platform.isMacOS) {
      // Approximate free as pages free * page size; best-effort only.
      final pageSize = _sysctlInt('hw.pagesize') ?? 4096;
      final freePages = _sysctlInt('vm.page_free_count');
      if (freePages == null) return null;
      return freePages * pageSize;
    }
    return null;
  }

  static double? _readLoadAverage1m() {
    if (!Platform.isLinux) return null;
    try {
      final text = File('/proc/loadavg').readAsStringSync();
      final first = text.split(RegExp(r'\s+')).first;
      return double.tryParse(first);
    } catch (_) {
      return null;
    }
  }

  static int? _meminfoKb(String key) {
    try {
      for (final line in File('/proc/meminfo').readAsLinesSync()) {
        if (!line.startsWith(key)) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) return null;
        return int.tryParse(parts[1]);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static int? _sysctlInt(String name) {
    try {
      final result = Process.runSync('sysctl', ['-n', name]);
      if (result.exitCode != 0) return null;
      return int.tryParse((result.stdout as String).trim());
    } catch (_) {
      return null;
    }
  }
}
