/// Per-binding CPU / RSS sample from a host process sweep.
class ResourceLeafMetrics {
  const ResourceLeafMetrics({
    this.cpu,
    this.memoryBytes,
    this.pid,
  });

  /// Percent of a single core (may exceed 100 on multi-core).
  final double? cpu;

  /// Resident set size in bytes (subtree sum when available).
  final int? memoryBytes;

  final int? pid;
}

/// Host machine memory / load sample.
class ResourceHostMemory {
  const ResourceHostMemory({
    required this.totalMemory,
    required this.freeMemory,
    required this.usedMemory,
    required this.memoryUsagePercent,
    this.cpuCoreCount,
    this.loadAverage1m,
  });

  final int totalMemory;
  final int freeMemory;
  final int usedMemory;
  final double memoryUsagePercent;
  final int? cpuCoreCount;
  final double? loadAverage1m;
}

/// Optional Flutter / Dart VM process usage.
class ResourceAppMemory {
  const ResourceAppMemory({
    this.cpu,
    this.memoryBytes,
    this.history = const [],
  });

  final double? cpu;
  final int? memoryBytes;

  /// Oldest-first memory samples (bytes) for sparklines.
  final List<int> history;
}

/// Last successful (or attempted) host metrics snapshot for Resource Manager.
class ResourceMemorySnapshot {
  const ResourceMemorySnapshot({
    required this.collectedAt,
    this.totalCpu,
    this.totalMemory,
    this.host,
    this.app,
    this.leafMetrics = const {},
    this.groupHistory = const {},
    this.totalMemoryHistory = const [],
  });

  final DateTime collectedAt;

  /// Sum of app + tracked leaves that have values (single-core %).
  final double? totalCpu;

  /// Sum of app + tracked leaves that have values (bytes).
  final int? totalMemory;

  final ResourceHostMemory? host;
  final ResourceAppMemory? app;

  /// Metrics keyed by [ResourceBinding.key]. Unmatched keys are ignored at merge.
  final Map<String, ResourceLeafMetrics> leafMetrics;

  /// Oldest-first memory samples (bytes) per worktree [groupKey].
  final Map<String, List<int>> groupHistory;

  /// Oldest-first total tracked memory samples for the totals sparkline.
  final List<int> totalMemoryHistory;
}
