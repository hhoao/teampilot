import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../router/app_router.dart';
import '../../utils/logging/logger_utils.dart';

/// Debug-only loopback driver for live performance capture on real app data.
///
/// Compile in with `--dart-define=PERF_DRIVER=true`. No-ops otherwise.
class LivePerfDriver {
  LivePerfDriver._();

  static const enabled = bool.fromEnvironment(
    'PERF_DRIVER',
    defaultValue: false,
  );
  static const port = int.fromEnvironment(
    'PERF_DRIVER_PORT',
    defaultValue: 17999,
  );

  static LivePerfDriver? _instance;

  /// Starts the driver when [enabled]; safe to call multiple times.
  static Future<void> ensureStarted() async {
    if (!enabled) return;
    if (_instance != null) return;
    final driver = LivePerfDriver._();
    await driver._start();
    _instance = driver;
  }

  static LivePerfDriver? get instance => _instance;

  HttpServer? _server;
  var _appReady = false;
  var _capturing = false;
  final _timings = <FrameTiming>[];

  bool get isAppReady => _appReady;

  void markAppReady() {
    _appReady = true;
    AppLogger.instance.i('LivePerfDriver app ready (port $port)');
  }

  Future<void> _start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } on SocketException catch (e, st) {
      AppLogger.instance.w(
        'LivePerfDriver bind failed on $port: $e',
        error: e,
        stackTrace: st,
      );
      return;
    }
    AppLogger.instance.i(
      'LivePerfDriver listening on http://127.0.0.1:$port/',
    );
    unawaited(_serve());
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      try {
        await _handle(request);
      } on Object catch (e, st) {
        AppLogger.instance.w(
          'LivePerfDriver request failed: $e',
          error: e,
          stackTrace: st,
        );
        if (request.response.connectionInfo != null) {
          try {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write(jsonEncode({'ok': false, 'error': '$e'}));
            await request.response.close();
          } on Object {
            // Response may already be closed.
          }
        }
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    switch (path) {
      case '/health':
        await _json(request, {
          'ok': true,
          'ready': _appReady,
          'capturing': _capturing,
          'port': port,
        });
        return;
      case '/vm-service':
        final info = await developer.Service.getInfo();
        await _json(request, {
          'ok': true,
          'uri': info.serverUri?.toString(),
        });
        return;
      case '/go':
        if (request.method != 'POST') {
          await _methodNotAllowed(request);
          return;
        }
        if (!_appReady) {
          await _json(request, {
            'ok': false,
            'error': 'app not ready',
          }, status: HttpStatus.serviceUnavailable);
          return;
        }
        final body = await utf8.decoder.bind(request).join();
        final map = body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(body) as Map<String, dynamic>;
        final location = (map['location'] as String?)?.trim() ?? '';
        if (location.isEmpty) {
          await _json(request, {
            'ok': false,
            'error': 'location required',
          }, status: HttpStatus.badRequest);
          return;
        }
        appRouter.go(location);
        await _json(request, {'ok': true, 'location': location});
        return;
      case '/capture/start':
        if (request.method != 'POST') {
          await _methodNotAllowed(request);
          return;
        }
        _startCapture();
        await _json(request, {'ok': true, 'capturing': true});
        return;
      case '/capture/stop':
        if (request.method != 'POST') {
          await _methodNotAllowed(request);
          return;
        }
        final frames = _stopCapture();
        await _json(request, {'ok': true, 'frames': frames});
        return;
      default:
        request.response.statusCode = HttpStatus.notFound;
        await _json(request, {'ok': false, 'error': 'not found'});
    }
  }

  void _startCapture() {
    if (_capturing) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    }
    _timings.clear();
    _capturing = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  List<Map<String, int>> _stopCapture() {
    if (_capturing) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _capturing = false;
    }
    return [
      for (final timing in _timings)
        {
          'number': timing.frameNumber,
          'startTime': timing.timestampInMicroseconds(FramePhase.vsyncStart),
          'elapsed': timing.totalSpan.inMicroseconds,
          'build': timing.buildDuration.inMicroseconds,
          'raster': timing.rasterDuration.inMicroseconds,
          'vsyncOverhead': timing.vsyncOverhead.inMicroseconds,
        },
    ];
  }

  void _onTimings(List<FrameTiming> timings) => _timings.addAll(timings);

  Future<void> _methodNotAllowed(HttpRequest request) async {
    await _json(request, {
      'ok': false,
      'error': 'method not allowed',
    }, status: HttpStatus.methodNotAllowed);
  }

  Future<void> _json(
    HttpRequest request,
    Map<String, Object?> body, {
    int status = HttpStatus.ok,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  @visibleForTesting
  Future<void> debugClose() async {
    if (_capturing) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _capturing = false;
    }
    await _server?.close(force: true);
    _server = null;
  }
}
