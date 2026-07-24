import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource_manager/process_metrics_service.dart';
import 'package:teampilot/services/resource_manager/process_table_parser.dart';
import 'package:teampilot/services/resource_manager/resource_memory_models.dart';

void main() {
  late String unixFixture;

  const fakeHost = ResourceHostMemory(
    totalMemory: 16 * 1024 * 1024 * 1024,
    freeMemory: 8 * 1024 * 1024 * 1024,
    usedMemory: 8 * 1024 * 1024 * 1024,
    memoryUsagePercent: 50,
    cpuCoreCount: 8,
    loadAverage1m: 1.25,
  );

  setUpAll(() {
    final dir = Directory.current.path.endsWith('client')
        ? Directory.current.path
        : '${Directory.current.path}/client';
    unixFixture = File(
      '$dir/test/services/resource_manager/fixtures/ps_unix.txt',
    ).readAsStringSync();
  });

  ProcessMetricsService buildService({
    Future<String> Function()? readProcessTable,
    Future<ResourceHostMemory?> Function()? readHostMemory,
    int Function()? appPid,
  }) {
    return ProcessMetricsService(
      readProcessTable: readProcessTable ?? () async => unixFixture,
      readHostMemory: readHostMemory ?? () async => fakeHost,
      appPid: appPid ?? () => 1,
      // Fixture is Unix `ps` text; default parser follows Platform.isWindows.
      parseProcessTable: parseUnixProcessTable,
    );
  }

  test('coalesces concurrent collect into one sweep', () async {
    var calls = 0;
    final svc = buildService(
      readProcessTable: () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return unixFixture;
      },
    );

    final a = svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );
    final b = svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );
    await Future.wait([a, b]);

    expect(calls, 1);
  });

  test('appends history and caps at 30', () async {
    final svc = buildService();
    final registered = {'chat:s1:m1': 42};
    final groups = {'chat:s1:m1': 'main'};

    ResourceMemorySnapshot? last;
    for (var i = 0; i < 35; i++) {
      last = await svc.collect(
        registeredPids: registered,
        bindingKeyToGroupKey: groups,
      );
    }

    expect(last, isNotNull);
    expect(last!.app?.history, hasLength(30));
    expect(last.groupHistory['main'], hasLength(30));
    expect(last.totalMemoryHistory, hasLength(30));

    // Oldest-first: first sample still present only after shift of 5.
    // Subtree of pid 42: (20480 + 4096) KB.
    const leafMem = (20480 + 4096) * 1024;
    // App pid 1 is self-only (not the PTY subtree).
    const appMem = 1024 * 1024;
    expect(last.app!.history.last, appMem);
    expect(last.groupHistory['main']!.last, leafMem);
    expect(last.totalMemoryHistory.last, appMem + leafMem);
  });

  test('missing pid yields null leaf metrics', () async {
    final svc = buildService();
    final snap = await svc.collect(
      registeredPids: {'chat:s1:m1': 99999},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );

    expect(snap.leafMetrics.containsKey('chat:s1:m1'), isTrue);
    final leaf = snap.leafMetrics['chat:s1:m1']!;
    expect(leaf.cpu, isNull);
    expect(leaf.memoryBytes, isNull);
  });

  test('failure returns last-good or empty without throwing', () async {
    var shouldFail = false;
    final svc = buildService(
      readProcessTable: () async {
        if (shouldFail) {
          throw StateError('sweep failed');
        }
        return unixFixture;
      },
    );

    final good = await svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );
    expect(good.leafMetrics['chat:s1:m1']?.memoryBytes, isNotNull);

    shouldFail = true;
    final afterFail = await svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );
    expect(afterFail.leafMetrics['chat:s1:m1']?.memoryBytes, isNotNull);
    expect(
      afterFail.leafMetrics['chat:s1:m1']!.memoryBytes,
      good.leafMetrics['chat:s1:m1']!.memoryBytes,
    );

    // Fresh service with no prior success → empty, no throw.
    final emptySvc = buildService(
      readProcessTable: () async => throw StateError('always'),
    );
    final empty = await emptySvc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );
    expect(empty.leafMetrics, isEmpty);
    expect(empty.app, isNull);
    expect(empty.host, isNull);
  });

  test('timeout-empty table returns last-good without overwriting', () async {
    var returnEmpty = false;
    final svc = buildService(
      readProcessTable: () async {
        if (returnEmpty) return '';
        return unixFixture;
      },
    );

    final good = await svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );
    expect(good.totalMemory, isNotNull);
    expect(good.leafMetrics['chat:s1:m1']?.memoryBytes, isNotNull);

    returnEmpty = true;
    final afterEmpty = await svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );

    expect(afterEmpty.totalMemory, good.totalMemory);
    expect(
      afterEmpty.leafMetrics['chat:s1:m1']?.memoryBytes,
      good.leafMetrics['chat:s1:m1']?.memoryBytes,
    );
    expect(
      afterEmpty.leafMetrics['chat:s1:m1']?.cpu,
      good.leafMetrics['chat:s1:m1']?.cpu,
    );
  });

  test('groupHistory retained when all pids in a group go missing', () async {
    var table = unixFixture;
    final svc = buildService(
      readProcessTable: () async => table,
    );

    final good = await svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );
    expect(good.groupHistory['main'], isNotEmpty);
    final priorRing = List<int>.of(good.groupHistory['main']!);

    // Table without pid 42/43 — binding still maps to group "main".
    table = '''
PID PPID %CPU RSS
1 0 0.0 1024
''';
    final missing = await svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );

    expect(missing.leafMetrics['chat:s1:m1']?.memoryBytes, isNull);
    expect(missing.groupHistory['main'], priorRing);
  });

  test('sums subtree for registered pid and includes host + app', () async {
    final svc = buildService();
    final snap = await svc.collect(
      registeredPids: {'chat:s1:m1': 42},
      bindingKeyToGroupKey: {'chat:s1:m1': 'main'},
    );

    expect(snap.host?.totalMemory, fakeHost.totalMemory);
    expect(snap.leafMetrics['chat:s1:m1']?.cpu, 1.7);
    expect(snap.leafMetrics['chat:s1:m1']?.memoryBytes, (20480 + 4096) * 1024);
    expect(snap.leafMetrics['chat:s1:m1']?.pid, 42);
    // App is Flutter/Dart self only (Orca uses Electron app metrics, not the
    // full process subtree — otherwise every PTY/agent is counted twice).
    expect(snap.app?.cpu, 0.0);
    expect(snap.app?.memoryBytes, 1024 * 1024);
    expect(snap.totalCpu, closeTo(0.0 + 1.7, 0.001));
    expect(
      snap.totalMemory,
      1024 * 1024 + (20480 + 4096) * 1024,
    );
  });

  test('does not double-count PTY subtree inside app or across leaves', () async {
    // App=1, leafA=42→43, leafB=43 (shared descendant of A).
    final svc = buildService();
    final snap = await svc.collect(
      registeredPids: {
        'chat:s1:a': 42,
        'chat:s1:b': 43,
      },
      bindingKeyToGroupKey: {
        'chat:s1:a': 'main',
        'chat:s1:b': 'main',
      },
    );

    expect(snap.app?.memoryBytes, 1024 * 1024);
    // First leaf claims 42+43; second leaf finds 43 already claimed → 0.
    expect(snap.leafMetrics['chat:s1:a']?.memoryBytes, (20480 + 4096) * 1024);
    expect(snap.leafMetrics['chat:s1:b']?.memoryBytes, 0);
    expect(
      snap.totalMemory,
      1024 * 1024 + (20480 + 4096) * 1024,
    );
  });

  // Orca: `ps -eo pid=,ppid=,pcpu=,rss=` — one format string. Splitting into
  // separate argv tokens makes Linux ps treat later tokens as PID lists and
  // exit 1 with an empty table (all Resource Manager CPU/Mem become —).
  test('unix ps argv is a single -eo format string like Orca', () {
    expect(
      ProcessMetricsService.unixPsArgs,
      ['-eo', 'pid=,ppid=,pcpu=,rss='],
    );
  });

  test('real unix ps with unixPsArgs returns a non-empty table', () async {
    if (Platform.isWindows || Platform.isAndroid) return;

    final result = await Process.run(
      'ps',
      ProcessMetricsService.unixPsArgs,
      environment: {
        ...Platform.environment,
        'LC_ALL': 'C',
        'LANG': 'C',
      },
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect((result.stdout as String).trim(), isNotEmpty);
  });
}
