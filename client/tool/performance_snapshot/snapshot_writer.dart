import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Builds a [PerformanceSnapshot] from an automated VM/timeline capture.
PerformanceSnapshot buildCapturedSnapshot({
  required List<FlutterFrame> frames,
  required List<int> traceBinary,
  required double displayRefreshRateHz,
  String? flutterVersion,
  bool isProfileBuild = false,
}) {
  return PerformanceSnapshot(
    devToolsVersion: 'teampilot-automated-capture',
    isDevToolsSnapshot: true,
    activeScreenId: 'performance',
    connectedApp: ConnectedAppInfo(
      flutterVersion: flutterVersion,
      operatingSystem: Platform.operatingSystem,
      isProfileBuild: isProfileBuild,
      isRunningOnDartVM: true,
    ),
    displayRefreshRateHz: displayRefreshRateHz,
    selectedFrameId: null,
    selectedTab: 0,
    frames: frames,
    rebuildData: null,
    traceBinary: traceBinary.isEmpty ? null : traceBinary,
  );
}

/// Writes a DevTools-compatible performance JSON file for [loadSnapshotFromFile].
Future<void> writeDevToolsSnapshotFile(
  String path,
  PerformanceSnapshot snapshot,
) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(_toJson(snapshot)),
  );
}

Map<String, dynamic> _toJson(PerformanceSnapshot snapshot) {
  final app = snapshot.connectedApp;
  return {
    'devToolsSnapshot': snapshot.isDevToolsSnapshot,
    'devToolsVersion': snapshot.devToolsVersion,
    'activeScreenId': snapshot.activeScreenId,
    'connectedApp': {
      'flutterVersion': app?.flutterVersion,
      'operatingSystem': app?.operatingSystem,
      'isProfileBuild': app?.isProfileBuild ?? false,
      'isRunningOnDartVM': app?.isRunningOnDartVM ?? true,
    },
    'performance': {
      'displayRefreshRate': snapshot.displayRefreshRateHz,
      'flutterFrames': [
        for (final frame in snapshot.frames)
          {
            'number': frame.number,
            'startTime': frame.startTimeUs,
            'elapsed': frame.elapsedUs,
            'build': frame.buildUs,
            'raster': frame.rasterUs,
            'vsyncOverhead': frame.vsyncUs,
          },
      ],
      'traceBinary': snapshot.traceBinary,
      'rebuildCountModel': null,
      'selectedFrameId': snapshot.selectedFrameId,
      'selectedTab': snapshot.selectedTab,
    },
  };
}
