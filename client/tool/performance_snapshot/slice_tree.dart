import 'trace_decoder.dart';

/// One node in a nested Perfetto slice tree (parent/child by time containment).
class SliceTreeNode {
  SliceTreeNode(this.slice);

  final TraceSlice slice;
  final List<SliceTreeNode> children = [];

  /// Set when [pruneSliceTreeTopPerLevel] drops lower-ranked siblings.
  int omittedSiblingCount = 0;
  double omittedSiblingSelfMs = 0;

  double get totalMs => slice.durationMs;

  double selfMs(List<SliceTreeNode> kids) =>
      totalMs - kids.fold<double>(0, (sum, c) => sum + c.totalMs);

  /// Direct-child [selfMs] after [children] are populated.
  double get selfMsDirect =>
      totalMs - children.fold<double>(0, (sum, c) => sum + c.totalMs);
}

/// How to rank siblings when applying per-level top-N pruning.
enum SliceTreeRankMetric {
  self,
  total,
}

bool sliceContains(TraceSlice parent, TraceSlice child) {
  if (parent.track != child.track) return false;
  return child.startNs >= parent.startNs && child.endNs <= parent.endNs;
}

/// Builds a forest of nested slice trees on each track independently.
List<SliceTreeNode> buildSliceForest(List<TraceSlice> slices) {
  if (slices.isEmpty) return const [];

  final byTrack = <String, List<TraceSlice>>{};
  for (final slice in slices) {
    byTrack.putIfAbsent(slice.track, () => []).add(slice);
  }

  final roots = <SliceTreeNode>[];
  for (final trackSlices in byTrack.values) {
    roots.addAll(_buildTrackForest(trackSlices));
  }
  roots.sort((a, b) => b.totalMs.compareTo(a.totalMs));
  return roots;
}

List<SliceTreeNode> _buildTrackForest(List<TraceSlice> slices) {
  final sorted = [...slices]
    ..sort((a, b) {
      final start = a.startNs.compareTo(b.startNs);
      if (start != 0) return start;
      return b.durationNs.compareTo(a.durationNs);
    });

  final roots = <SliceTreeNode>[];
  final active = <SliceTreeNode>[];

  for (final slice in sorted) {
    final node = SliceTreeNode(slice);
    while (active.isNotEmpty && !sliceContains(active.last.slice, slice)) {
      active.removeLast();
    }
    if (active.isEmpty) {
      roots.add(node);
    } else {
      active.last.children.add(node);
    }
    active.add(node);
  }

  _sortChildrenBySelfTime(roots);
  return roots;
}

void _sortChildrenBySelfTime(List<SliceTreeNode> nodes) {
  for (final node in nodes) {
    node.children.sort((a, b) => b.selfMsDirect.compareTo(a.selfMsDirect));
    _sortChildrenBySelfTime(node.children);
  }
}

/// Depth-first flatten with breadcrumb paths, sorted by self time.
List<SliceSelfTimeEntry> collectSelfTimeHotspots(
  List<SliceTreeNode> roots, {
  required double minSelfMs,
  int limit = 40,
}) {
  final entries = <SliceSelfTimeEntry>[];
  void walk(SliceTreeNode node, List<String> path) {
    final name = node.slice.name;
    final nextPath = [...path, name];
    final self = node.selfMsDirect;
    if (self >= minSelfMs) {
      entries.add(
        SliceSelfTimeEntry(
          name: name,
          track: node.slice.trackLabel,
          totalMs: node.totalMs,
          selfMs: self,
          path: nextPath.join(' › '),
        ),
      );
    }
    for (final child in node.children) {
      walk(child, nextPath);
    }
  }

  for (final root in roots) {
    walk(root, const []);
  }
  entries.sort((a, b) => b.selfMs.compareTo(a.selfMs));
  if (entries.length > limit) return entries.sublist(0, limit);
  return entries;
}

class SliceSelfTimeEntry {
  const SliceSelfTimeEntry({
    required this.name,
    required this.track,
    required this.totalMs,
    required this.selfMs,
    required this.path,
  });

  final String name;
  final String track;
  final double totalMs;
  final double selfMs;
  final String path;
}

/// Prunes child subtrees below [maxDepth] (0 = roots only).
void pruneSliceTreeDepth(List<SliceTreeNode> nodes, int maxDepth, [int depth = 0]) {
  if (depth >= maxDepth) {
    for (final node in nodes) {
      node.children.clear();
    }
    return;
  }
  for (final node in nodes) {
    pruneSliceTreeDepth(node.children, maxDepth, depth + 1);
  }
}

/// Drops nodes whose inclusive duration is below [minTotalMs].
void pruneSliceTreeMinTotal(List<SliceTreeNode> nodes, double minTotalMs) {
  nodes.removeWhere((n) => n.totalMs < minTotalMs);
  for (final node in nodes) {
    pruneSliceTreeMinTotal(node.children, minTotalMs);
  }
}

/// Summary of siblings dropped when trimming the root forest.
class SliceTreeForestOmitted {
  const SliceTreeForestOmitted({
    required this.count,
    required this.selfMs,
  });

  final int count;
  final double selfMs;
}

/// At every tree level, keeps only the top [topK] children by [metric], then
/// recurses into each survivor. Dropped siblings are recorded on the parent
/// ([SliceTreeNode.omittedSiblingCount]) or in [SliceTreeForestOmitted] for
/// the root forest.
SliceTreeForestOmitted? pruneSliceTreeTopPerLevel(
  List<SliceTreeNode> roots, {
  required int topK,
  SliceTreeRankMetric metric = SliceTreeRankMetric.self,
}) {
  if (topK <= 0) return null;

  // Root forest: rank by inclusive time so outer phases (e.g. LAYOUT) survive.
  final forestOmitted = _trimSiblingList(
    roots,
    topK: topK,
    metric: SliceTreeRankMetric.total,
  );
  for (final root in roots) {
    _pruneTopPerLevelRecursive(root, topK: topK, metric: metric);
  }
  return forestOmitted;
}

void _pruneTopPerLevelRecursive(
  SliceTreeNode node, {
  required int topK,
  required SliceTreeRankMetric metric,
}) {
  final omitted = _trimSiblingList(node.children, topK: topK, metric: metric);
  if (omitted != null) {
    node.omittedSiblingCount = omitted.count;
    node.omittedSiblingSelfMs = omitted.selfMs;
  }
  for (final child in node.children) {
    _pruneTopPerLevelRecursive(child, topK: topK, metric: metric);
  }
}

/// Trims [siblings] to [topK] by [metric]. Returns omitted stats when trimming.
SliceTreeForestOmitted? _trimSiblingList(
  List<SliceTreeNode> siblings, {
  required int topK,
  required SliceTreeRankMetric metric,
}) {
  if (siblings.length <= topK) return null;

  double rank(SliceTreeNode n) => switch (metric) {
        SliceTreeRankMetric.self => n.selfMsDirect,
        SliceTreeRankMetric.total => n.totalMs,
      };

  siblings.sort((a, b) => rank(b).compareTo(rank(a)));
  final dropped = siblings.sublist(topK);
  final droppedSelf = dropped.fold<double>(0, (s, n) => s + n.selfMsDirect);
  siblings.removeRange(topK, siblings.length);

  return SliceTreeForestOmitted(count: dropped.length, selfMs: droppedSelf);
}
