import 'dart:convert';
import 'dart:developer' show Service;
import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'models.dart';
import 'snapshot_writer.dart';

/// Records frame timings + Perfetto timeline via the in-process VM service.
///
/// Intended for integration / performance tests (`flutter test`), not `dart run`.
class VmPerformanceCapture {
  VmService? _service;
  final List<FrameTiming> _timings = [];

  void _onTimings(List<FrameTiming> timings) => _timings.addAll(timings);

  Future<void> start() async {
    _timings.clear();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _service = await _connectVmService();
    await _service!.setVMTimelineFlags(['Dart', 'GC', 'Embedder']);
    await _service!.clearVMTimeline();
  }

  Future<PerformanceSnapshot> stop({
    double? displayRefreshRateHz,
    String? flutterVersion,
    bool isProfileBuild = false,
  }) async {
    final service = _service;
    if (service == null) {
      throw StateError('VmPerformanceCapture.start() was not called');
    }

    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    final perfetto = await service.getPerfettoVMTimeline();
    await service.dispose();
    _service = null;

    final traceText = perfetto.trace ?? '';
    final traceBinary = traceText.isEmpty ? <int>[] : base64.decode(traceText);
    final refreshRate =
        displayRefreshRateHz ??
        SchedulerBinding.instance.platformDispatcher.displays.first.refreshRate;

    return buildCapturedSnapshot(
      frames: _framesFromTimings(_timings),
      traceBinary: traceBinary,
      displayRefreshRateHz: refreshRate,
      flutterVersion: flutterVersion,
      isProfileBuild: isProfileBuild,
    );
  }

  Future<void> stopAndWrite(
    String outputPath, {
    double? displayRefreshRateHz,
    String? flutterVersion,
    bool isProfileBuild = false,
  }) async {
    final snapshot = await stop(
      displayRefreshRateHz: displayRefreshRateHz,
      flutterVersion: flutterVersion,
      isProfileBuild: isProfileBuild,
    );
    await writeDevToolsSnapshotFile(outputPath, snapshot);
  }
}

Future<VmService> _connectVmService() async {
  final info = await Service.getInfo();
  final serverUri = info.serverUri;
  if (serverUri == null) {
    throw StateError(
      'VM service unavailable — run via `flutter test`, not `dart test`.',
    );
  }
  var uri = serverUri;
  if (uri.scheme == 'http') {
    uri = uri.replace(scheme: 'ws');
  }
  return vmServiceConnectUri(uri.toString());
}

List<FlutterFrame> _framesFromTimings(List<FrameTiming> timings) {
  return [
    for (final timing in timings)
      FlutterFrame(
        number: timing.frameNumber,
        startTimeUs: timing.timestampInMicroseconds(FramePhase.vsyncStart),
        elapsedUs: timing.totalSpan.inMicroseconds,
        buildUs: timing.buildDuration.inMicroseconds,
        rasterUs: timing.rasterDuration.inMicroseconds,
        vsyncUs: timing.vsyncOverhead.inMicroseconds,
      ),
  ];
}
