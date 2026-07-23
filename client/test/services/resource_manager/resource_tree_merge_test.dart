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
    expect(vm.groups.single.leaves.single.cpuDisplay, '1.5%');
    expect(vm.groups.single.aggregateMemoryBytes, 10 * 1024 * 1024);
  });

  test('main and main-worktree groups sort before other groupKeys', () {
    final bindings = [
      ResourceBinding(
        key: 'chat:s1:m1',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'feature-a',
        groupLabel: 'feature-a',
        title: 'Feature terminal',
        connected: true,
        sessionId: 's1',
        memberId: 'm1',
      ),
      ResourceBinding(
        key: 'chat:s2:m1',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'main-worktree',
        groupLabel: 'main-worktree',
        title: 'Main worktree terminal',
        connected: true,
        sessionId: 's2',
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
      ResourceBinding(
        key: 'chat:s3:m1',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'zebra',
        groupLabel: 'zebra',
        title: 'Zebra terminal',
        connected: true,
        sessionId: 's3',
        memberId: 'm1',
      ),
    ];
    final vm = mergeResourceTree(bindings: bindings, snapshot: null);
    expect(
      vm.groups.map((g) => g.groupKey).toList(),
      ['main', 'main-worktree', 'feature-a', 'zebra'],
    );
  });

  test('leaves within a group are sorted by title', () {
    final bindings = [
      ResourceBinding(
        key: 'chat:s1:m2',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Zebra',
        connected: true,
        sessionId: 's1',
        memberId: 'm2',
      ),
      ResourceBinding(
        key: 'chat:s1:m1',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Alpha',
        connected: true,
        sessionId: 's1',
        memberId: 'm1',
      ),
      ResourceBinding(
        key: 'shell:w1:e1',
        kind: ResourceBindingKind.workspaceShell,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Middle',
        connected: false,
        workspaceId: 'w1',
        shellEntryId: 'e1',
      ),
    ];
    final vm = mergeResourceTree(bindings: bindings, snapshot: null);
    expect(
      vm.groups.single.leaves.map((l) => l.title).toList(),
      ['Alpha', 'Middle', 'Zebra'],
    );
  });

  test('aggregates cpu and memory across matched leaves excluding nulls', () {
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
        key: 'chat:s1:m2',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Terminal 2',
        connected: true,
        sessionId: 's1',
        memberId: 'm2',
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
    final snapshot = ResourceMemorySnapshot(
      collectedAt: DateTime.utc(2026, 1, 1),
      leafMetrics: {
        'chat:s1:m1': const ResourceLeafMetrics(
          cpu: 1.5,
          memoryBytes: 10 * 1024 * 1024,
        ),
        'chat:s1:m2': const ResourceLeafMetrics(
          cpu: 2.5,
          memoryBytes: 20 * 1024 * 1024,
        ),
        // shell:w1:e1 intentionally omitted → null metrics excluded from sum
      },
    );
    final vm = mergeResourceTree(bindings: bindings, snapshot: snapshot);
    expect(vm.groups.single.leaves, hasLength(3));
    expect(vm.groups.single.aggregateCpu, 4.0);
    expect(vm.groups.single.aggregateMemoryBytes, 30 * 1024 * 1024);
    expect(
      vm.groups.single.leaves.map((l) => l.cpuDisplay).toList(),
      ['—', '1.5%', '2.5%'], // title order: Shell, Terminal 1, Terminal 2
    );
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
