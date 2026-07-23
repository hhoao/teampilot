import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/resource_manager_cubit.dart';
import 'package:teampilot/services/resource_manager/process_metrics_service.dart';
import 'package:teampilot/services/resource_manager/pty_process_registry.dart';
import 'package:teampilot/services/resource_manager/resource_binding.dart';
import 'package:teampilot/services/resource_manager/resource_memory_models.dart';

class FakeProcessMetricsService extends ProcessMetricsService {
  FakeProcessMetricsService();

  int collectCount = 0;
  Object? throwOnCollect;
  ResourceMemorySnapshot Function(
    Map<String, int> registeredPids,
    Map<String, String> bindingKeyToGroupKey,
  )?
  onCollect;

  @override
  Future<ResourceMemorySnapshot> collect({
    required Map<String, int> registeredPids,
    required Map<String, String> bindingKeyToGroupKey,
  }) async {
    collectCount++;
    final err = throwOnCollect;
    if (err != null) {
      throw err;
    }
    final builder = onCollect;
    if (builder != null) {
      return builder(registeredPids, bindingKeyToGroupKey);
    }
    return ResourceMemorySnapshot(
      collectedAt: DateTime.fromMillisecondsSinceEpoch(collectCount * 1000),
      totalMemory: collectCount * 1024,
      leafMetrics: {
        for (final e in registeredPids.entries)
          e.key: ResourceLeafMetrics(pid: e.value, memoryBytes: 2048, cpu: 1.0),
      },
    );
  }
}

ResourceBinding _binding({
  required String key,
  String groupKey = 'main',
  String title = 'leaf',
  int? livePid,
  bool connected = true,
}) {
  return ResourceBinding(
    key: key,
    kind: ResourceBindingKind.chatMember,
    groupKey: groupKey,
    groupLabel: groupKey,
    title: title,
    connected: connected,
    sessionId: 's1',
    memberId: key,
    livePid: livePid,
  );
}

void main() {
  late FakeProcessMetricsService metrics;
  late PtyProcessRegistry registry;
  late List<ResourceBinding> bindings;
  late List<String> killed;
  late Object? killError;
  late ResourceManagerCubit cubit;

  const pollInterval = Duration(milliseconds: 30);

  ResourceManagerCubit buildCubit() {
    return ResourceManagerCubit(
      metricsService: metrics,
      registry: registry,
      bindingsSource: () => List<ResourceBinding>.of(bindings),
      killBinding: (key) async {
        if (killError != null) {
          throw killError!;
        }
        killed.add(key);
      },
      pollInterval: pollInterval,
    );
  }

  setUp(() {
    metrics = FakeProcessMetricsService();
    registry = PtyProcessRegistry();
    bindings = [
      _binding(key: 'chat:s1:m1', title: 'A', livePid: 42),
      _binding(key: 'chat:s1:m2', title: 'B', livePid: 43),
    ];
    killed = <String>[];
    killError = null;
    cubit = buildCubit();
  });

  tearDown(() async {
    await cubit.close();
  });

  test('open starts polling; close cancels', () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();
    expect(metrics.collectCount, greaterThanOrEqualTo(1));

    await Future<void>.delayed(pollInterval * 3);
    final whileOpen = metrics.collectCount;
    expect(whileOpen, greaterThanOrEqualTo(2));

    cubit.closePanel();
    expect(cubit.state.isOpen, isFalse);
    // Capture after stop so an in-flight tick started before close is allowed.
    final afterClose = metrics.collectCount;

    await Future<void>.delayed(pollInterval * 3);
    expect(metrics.collectCount, afterClose);
  });

  test('closed state does not call collect', () async {
    cubit.setWorkspace('ws-1');
    await Future<void>.delayed(pollInterval * 3);
    expect(metrics.collectCount, 0);
    expect(cubit.state.isOpen, isFalse);
  });

  test('refresh forces collect while open', () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();
    final afterOpen = metrics.collectCount;

    await cubit.refresh();
    expect(metrics.collectCount, greaterThan(afterOpen));
    expect(cubit.state.isOpen, isTrue);
  });

  test('workspace change closes panel and stops timer', () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();
    expect(cubit.state.isOpen, isTrue);

    await Future<void>.delayed(pollInterval * 2);

    cubit.setWorkspace('ws-2');
    expect(cubit.state.isOpen, isFalse);
    expect(cubit.state.workspaceId, 'ws-2');
    final afterChange = metrics.collectCount;

    await Future<void>.delayed(pollInterval * 3);
    expect(metrics.collectCount, afterChange);
  });

  test('killLeaf invokes injector once per key', () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();

    await cubit.killLeaf('chat:s1:m1');
    expect(killed, ['chat:s1:m1']);

    await cubit.killLeaf('chat:s1:m1');
    expect(killed, ['chat:s1:m1', 'chat:s1:m1']);
  });

  test('killAll invokes injector for each leaf', () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();

    await cubit.killAll();
    expect(killed.toSet(), {'chat:s1:m1', 'chat:s1:m2'});
    expect(killed, hasLength(2));
  });

  test('kill failure sets error and does not remove leaf until bindings refresh',
      () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();
    expect(cubit.state.terminalCount, 2);
    expect(cubit.state.tree?.terminalCount, 2);

    killError = Exception('kill failed');
    await cubit.killLeaf('chat:s1:m1');

    expect(cubit.state.error, isNotNull);
    expect(cubit.state.bindings.map((b) => b.key), contains('chat:s1:m1'));
    expect(cubit.state.terminalCount, 2);

    killError = null;
    bindings = [_binding(key: 'chat:s1:m2', title: 'B', livePid: 43)];
    await cubit.refresh();

    expect(cubit.state.bindings.map((b) => b.key), isNot(contains('chat:s1:m1')));
    expect(cubit.state.terminalCount, 1);
  });

  test('snapshot failure keeps last good snapshot and sets error', () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();
    final good = cubit.state.snapshot;
    expect(good, isNotNull);
    expect(good!.totalMemory, isNotNull);

    metrics.throwOnCollect = Exception('sweep failed');
    await cubit.refresh();

    expect(cubit.state.error, isNotNull);
    expect(identical(cubit.state.snapshot, good), isTrue);
    expect(cubit.state.snapshot?.totalMemory, good.totalMemory);
  });

  test('syncRegistry drops null livePid and replaces map', () async {
    registry.register(bindingKey: 'stale', pid: 99);
    registry.register(bindingKey: 'chat:s1:m1', pid: 1);

    bindings = [
      _binding(key: 'chat:s1:m1', title: 'A', livePid: null),
      _binding(key: 'chat:s1:m2', title: 'B', livePid: 43),
      _binding(key: 'chat:s1:m3', title: 'C', livePid: 44),
    ];

    cubit.setWorkspace('ws-1');
    cubit.syncRegistryFromBindings();

    expect(registry.asMap, {'chat:s1:m2': 43, 'chat:s1:m3': 44});
    expect(registry.pidFor('chat:s1:m1'), isNull);
    expect(registry.pidFor('stale'), isNull);
  });

  test('closePanel keeps last good snapshot for closed pill', () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();
    final snap = cubit.state.snapshot;
    expect(snap, isNotNull);

    cubit.closePanel();
    expect(cubit.state.isOpen, isFalse);
    expect(identical(cubit.state.snapshot, snap), isTrue);
  });

  test('onRouteActiveChanged(false) closes panel and stops polling', () async {
    cubit.setWorkspace('ws-1');
    await cubit.openPanel();
    await Future<void>.delayed(pollInterval * 2);

    cubit.onRouteActiveChanged(false);
    expect(cubit.state.isOpen, isFalse);
    final afterInactive = metrics.collectCount;

    await Future<void>.delayed(pollInterval * 3);
    expect(metrics.collectCount, afterInactive);
  });
}
