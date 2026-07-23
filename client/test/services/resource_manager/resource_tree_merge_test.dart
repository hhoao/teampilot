import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource_manager/resource_binding.dart';
import 'package:teampilot/services/resource_manager/resource_memory_models.dart';
import 'package:teampilot/services/resource_manager/resource_tree_merge.dart';

void main() {
  test('closed count is binding leaf count not host process count', () {
    final bindings = [
      ResourceBinding(
        key: 'chat:s1:m1',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Terminal 1',
        connected: true,
        sessionId: 's1',
        memberId: 'm1',
      ),
      ResourceBinding(
        key: 'shell:w1:e1',
        kind: ResourceBindingKind.workspaceShell,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Shell',
        connected: false,
        workspaceId: 'w1',
        shellEntryId: 'e1',
      ),
    ];
    final vm = mergeResourceTree(bindings: bindings, snapshot: null);
    expect(vm.terminalCount, 2);
    expect(vm.groups.single.leaves, hasLength(2));
    expect(vm.groups.single.leaves.first.cpuDisplay, '—');
  });

  test('merges metrics onto matching bindingKey and aggregates group', () {
    final bindings = [
      ResourceBinding(
        key: 'chat:s1:m1',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Terminal 1',
        connected: true,
        sessionId: 's1',
        memberId: 'm1',
      ),
    ];
    final snapshot = ResourceMemorySnapshot(
      collectedAt: DateTime.utc(2026, 1, 1),
      totalCpu: 1.5,
      totalMemory: 10 * 1024 * 1024,
      leafMetrics: {
        'chat:s1:m1': const ResourceLeafMetrics(
          cpu: 1.5,
          memoryBytes: 10 * 1024 * 1024,
        ),
      },
    );
    final vm = mergeResourceTree(bindings: bindings, snapshot: snapshot);
    expect(vm.groups.single.leaves.single.cpuDisplay, isNot('—'));
    expect(vm.groups.single.aggregateMemoryBytes, 10 * 1024 * 1024);
  });

  test('unmatched snapshot pids do not create extra leaves', () {
    final bindings = [
      ResourceBinding(
        key: 'chat:s1:m1',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Terminal 1',
        connected: true,
        sessionId: 's1',
        memberId: 'm1',
      ),
    ];
    final snapshot = ResourceMemorySnapshot(
      collectedAt: DateTime.utc(2026, 1, 1),
      leafMetrics: {
        'chat:other:x': const ResourceLeafMetrics(cpu: 9, memoryBytes: 99),
      },
    );
    final vm = mergeResourceTree(bindings: bindings, snapshot: snapshot);
    expect(vm.groups.single.leaves, hasLength(1));
    expect(vm.groups.single.leaves.single.cpuDisplay, '—');
  });
}
