import 'resource_binding.dart';
import 'resource_memory_format.dart';
import 'resource_memory_models.dart';

/// Merged Resource Manager tree ready for the status-bar panel.
class ResourceTreeViewModel {
  const ResourceTreeViewModel({
    required this.terminalCount,
    required this.groups,
    this.totalCpu,
    this.totalMemory,
  });

  /// Running session/shell leaf count (connected bindings), not host process count.
  final int terminalCount;
  final List<ResourceTreeGroupVm> groups;
  final double? totalCpu;
  final int? totalMemory;
}

class ResourceTreeGroupVm {
  const ResourceTreeGroupVm({
    required this.groupKey,
    required this.groupLabel,
    required this.leaves,
    this.aggregateCpu,
    this.aggregateMemoryBytes,
    this.memoryHistory = const [],
  });

  final String groupKey;
  final String groupLabel;
  final List<ResourceTreeLeafVm> leaves;
  final double? aggregateCpu;
  final int? aggregateMemoryBytes;
  final List<int> memoryHistory;
}

class ResourceTreeLeafVm {
  const ResourceTreeLeafVm({
    required this.key,
    required this.kind,
    required this.title,
    required this.connected,
    required this.cpuDisplay,
    required this.memoryDisplay,
    this.cpu,
    this.memoryBytes,
    this.pid,
    this.sessionId,
    this.memberId,
    this.workspaceId,
    this.shellEntryId,
  });

  final String key;
  final ResourceBindingKind kind;
  final String title;
  final bool connected;
  final String cpuDisplay;
  final String memoryDisplay;
  final double? cpu;
  final int? memoryBytes;
  final int? pid;
  final String? sessionId;
  final String? memberId;
  final String? workspaceId;
  final String? shellEntryId;
}

/// Pure merge: workspace bindings + optional snapshot → two-level tree VM.
ResourceTreeViewModel mergeResourceTree({
  required List<ResourceBinding> bindings,
  ResourceMemorySnapshot? snapshot,
}) {
  final leafMetrics = snapshot?.leafMetrics ?? const <String, ResourceLeafMetrics>{};
  final grouped = <String, _GroupAccumulator>{};

  for (final binding in bindings) {
    final metrics = leafMetrics[binding.key];
    final cpu = metrics?.cpu;
    final memoryBytes = metrics?.memoryBytes;
    final leaf = ResourceTreeLeafVm(
      key: binding.key,
      kind: binding.kind,
      title: binding.title,
      connected: binding.connected,
      cpu: cpu,
      memoryBytes: memoryBytes,
      pid: metrics?.pid,
      cpuDisplay: formatResourceCpu(cpu),
      memoryDisplay: formatResourceMemory(memoryBytes),
      sessionId: binding.sessionId,
      memberId: binding.memberId,
      workspaceId: binding.workspaceId,
      shellEntryId: binding.shellEntryId,
    );

    final acc = grouped.putIfAbsent(
      binding.groupKey,
      () => _GroupAccumulator(
        groupKey: binding.groupKey,
        groupLabel: binding.groupLabel,
      ),
    );
    acc.leaves.add(leaf);
    if (cpu != null) {
      acc.cpuSum = (acc.cpuSum ?? 0) + cpu;
    }
    if (memoryBytes != null) {
      acc.memorySum = (acc.memorySum ?? 0) + memoryBytes;
    }
  }

  final groups = grouped.values.map((acc) {
    final leaves = List<ResourceTreeLeafVm>.of(acc.leaves)
      ..sort((a, b) => a.title.compareTo(b.title));
    return ResourceTreeGroupVm(
      groupKey: acc.groupKey,
      groupLabel: acc.groupLabel,
      leaves: leaves,
      aggregateCpu: acc.cpuSum,
      aggregateMemoryBytes: acc.memorySum,
      memoryHistory: snapshot?.groupHistory[acc.groupKey] ?? const [],
    );
  }).toList()
    ..sort(_compareGroups);

  return ResourceTreeViewModel(
    terminalCount: bindings.length,
    groups: groups,
    totalCpu: snapshot?.totalCpu,
    totalMemory: snapshot?.totalMemory,
  );
}

class _GroupAccumulator {
  _GroupAccumulator({
    required this.groupKey,
    required this.groupLabel,
  });

  final String groupKey;
  final String groupLabel;
  final List<ResourceTreeLeafVm> leaves = [];
  double? cpuSum;
  int? memorySum;
}

int _compareGroups(ResourceTreeGroupVm a, ResourceTreeGroupVm b) {
  final aMain = _isMainGroup(a);
  final bMain = _isMainGroup(b);
  if (aMain != bMain) {
    return aMain ? -1 : 1;
  }
  return a.groupLabel.compareTo(b.groupLabel);
}

bool _isMainGroup(ResourceTreeGroupVm group) {
  final label = group.groupLabel.trim().toLowerCase();
  final key = group.groupKey.trim().toLowerCase();
  return label == 'main' ||
      label == 'main-worktree' ||
      key == 'main' ||
      key == 'main-worktree';
}
