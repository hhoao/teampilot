import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'rebuild_model.dart';

const performanceTabs = [
  'Frame Analysis',
  'Rebuild Stats',
  'Timeline Events',
];

String tabLabel(int? index) {
  if (index == null) return '';
  if (index >= 0 && index < performanceTabs.length) {
    return performanceTabs[index];
  }
  return 'tab $index';
}

RebuildDataStatus rebuildStatus(Object? raw) {
  if (raw == null) return RebuildDataStatus.notCaptured;
  if (raw is Map && raw.isEmpty) return RebuildDataStatus.empty;
  return RebuildDataStatus.present;
}

/// Loads a DevTools performance snapshot from a JSON file path.
PerformanceSnapshot loadSnapshotFromFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw SnapshotLoadException('File not found: $path');
  }
  return loadSnapshotFromJson(file.readAsStringSync());
}

/// Parses a DevTools performance snapshot from raw JSON text.
PerformanceSnapshot loadSnapshotFromJson(String jsonText) {
  final root = jsonDecode(jsonText) as Map<String, dynamic>;
  final perf = root['performance'] as Map<String, dynamic>?;
  if (perf == null) {
    throw SnapshotLoadException(
      'Not a DevTools performance snapshot (missing performance key).',
    );
  }
  return _parseSnapshot(root, perf);
}

class SnapshotLoadException implements Exception {
  SnapshotLoadException(this.message);
  final String message;

  @override
  String toString() => message;
}

PerformanceSnapshot _parseSnapshot(
  Map<String, dynamic> root,
  Map<String, dynamic> perf,
) {
  final app = root['connectedApp'] as Map<String, dynamic>?;
  ConnectedAppInfo? connectedApp;
  if (app != null) {
    connectedApp = ConnectedAppInfo(
      flutterVersion: app['flutterVersion'] as String?,
      operatingSystem: app['operatingSystem'] as String?,
      isProfileBuild: app['isProfileBuild'] as bool? ?? false,
      isRunningOnDartVM: app['isRunningOnDartVM'] as bool? ?? false,
    );
  }

  final traceRaw = perf['traceBinary'];
  List<int>? traceBinary;
  if (traceRaw is List) {
    traceBinary = traceRaw.cast<int>();
  }

  return PerformanceSnapshot(
    devToolsVersion: root['devToolsVersion'] as String?,
    isDevToolsSnapshot: root['devToolsSnapshot'] == true,
    activeScreenId: root['activeScreenId'] as String?,
    connectedApp: connectedApp,
    displayRefreshRateHz: (perf['displayRefreshRate'] as num?)?.toDouble() ?? 60,
    selectedFrameId: perf['selectedFrameId'] as int?,
    selectedTab: perf['selectedTab'] as int?,
    frames: _parseFrames(perf),
    rebuildData: RebuildCountData.fromJson(perf['rebuildCountModel']),
    traceBinary: traceBinary,
  );
}

List<FlutterFrame> _parseFrames(Map<String, dynamic> perf) {
  final raw = perf['flutterFrames'];
  if (raw is! List) return [];
  return [
    for (final item in raw)
      if (item is Map<String, dynamic>)
        FlutterFrame(
          number: item['number'] as int,
          startTimeUs: item['startTime'] as int,
          elapsedUs: item['elapsed'] as int,
          buildUs: item['build'] as int,
          rasterUs: item['raster'] as int,
          vsyncUs: item['vsyncOverhead'] as int,
        ),
  ];
}
