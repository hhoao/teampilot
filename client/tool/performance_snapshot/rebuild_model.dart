// ignore_for_file: avoid_print

class RebuildLocation {
  RebuildLocation({
    required this.id,
    required this.name,
    this.file,
    this.line,
    this.column,
    required this.buildCount,
  });

  final int id;
  final String name;
  final String? file;
  final int? line;
  final int? column;
  final int buildCount;

  String get label {
    if (file != null && line != null) {
      final col = column != null ? ':$column' : '';
      return '$name ($file:$line$col)';
    }
    return name;
  }
}

class RebuildCountData {
  RebuildCountData({
    required this.locationsById,
    required this.rebuildsByFrame,
    required this.totalsByLocationId,
  });

  final Map<int, RebuildLocation> locationsById;
  final Map<int, List<RebuildLocation>> rebuildsByFrame;
  final Map<int, int> totalsByLocationId;

  bool get isEmpty => rebuildsByFrame.isEmpty;

  static RebuildCountData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<String, Object?>();
    if (json.isEmpty) return null;

    final locationsById = <int, RebuildLocation>{};
    final locations = json['locations'];
    if (locations is Map) {
      for (final entry in locations.entries) {
        final file = entry.key;
        if (entry.value is! Map) continue;
        final loc = entry.value as Map;
        final ids = (loc['ids'] as List?)?.cast<int>() ?? const [];
        final lines = (loc['lines'] as List?)?.cast<int>() ?? const [];
        final columns = (loc['columns'] as List?)?.cast<int>() ?? const [];
        final names = (loc['names'] as List?)?.cast<String>() ?? const [];
        for (var i = 0; i < ids.length; i++) {
          locationsById[ids[i]] = RebuildLocation(
            id: ids[i],
            name: i < names.length ? names[i] : 'location:${ids[i]}',
            file: file,
            line: i < lines.length ? lines[i] : null,
            column: i < columns.length ? columns[i] : null,
            buildCount: 0,
          );
        }
      }
    }

    final rebuildsByFrame = <int, List<RebuildLocation>>{};
    final totalsByLocationId = <int, int>{};
    final frames = json['frames'];
    if (frames is List) {
      for (final frameRaw in frames) {
        if (frameRaw is! Map) continue;
        final frameNumber = frameRaw['frameNumber'];
        final events = frameRaw['events'];
        if (frameNumber is! int || events is! List) continue;

        final rebuilds = <RebuildLocation>[];
        for (var i = 0; i + 1 < events.length; i += 2) {
          final id = events[i];
          final count = events[i + 1];
          if (id is! int || count is! int) continue;

          final base = locationsById[id];
          final location = RebuildLocation(
            id: id,
            name: base?.name ?? 'location:$id',
            file: base?.file,
            line: base?.line,
            column: base?.column,
            buildCount: count,
          );
          rebuilds.add(location);
          totalsByLocationId[id] = (totalsByLocationId[id] ?? 0) + count;
        }
        rebuildsByFrame[frameNumber] = rebuilds;
      }
    }

    if (rebuildsByFrame.isEmpty && locationsById.isEmpty) return null;
    return RebuildCountData(
      locationsById: locationsById,
      rebuildsByFrame: rebuildsByFrame,
      totalsByLocationId: totalsByLocationId,
    );
  }

  List<RebuildLocation> topOverall({int limit = 25}) {
    final ranked = totalsByLocationId.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in ranked.take(limit))
        RebuildLocation(
          id: entry.key,
          name: locationsById[entry.key]?.name ?? 'location:${entry.key}',
          file: locationsById[entry.key]?.file,
          line: locationsById[entry.key]?.line,
          column: locationsById[entry.key]?.column,
          buildCount: entry.value,
        ),
    ];
  }
}
