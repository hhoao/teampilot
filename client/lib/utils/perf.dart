import 'dart:developer' as developer;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

/// Wrap a synchronous call with timeline events and debug logging.
/// Returns the result of [fn] after measuring its wall-clock duration.
T trackSync<T>(String label, T Function() fn) {
  developer.Timeline.startSync(label);
  final sw = Stopwatch()..start();
  try {
    return fn();
  } finally {
    sw.stop();
    developer.Timeline.finishSync();
    if (sw.elapsedMilliseconds > 8) {
      // ignore: avoid_print
      print('[perf] $label: ${sw.elapsedMilliseconds}ms');
    }
  }
}

/// Wrap an async call with timeline events and debug logging.
Future<T> trackAsync<T>(String label, Future<T> Function() fn) async {
  developer.Timeline.startSync(label);
  final sw = Stopwatch()..start();
  try {
    return await fn();
  } finally {
    sw.stop();
    developer.Timeline.finishSync();
    if (sw.elapsedMilliseconds > 16) {
      // ignore: avoid_print
      print('[perf] $label: ${sw.elapsedMilliseconds}ms');
    }
  }
}

class PerfMark {
  PerfMark(this.label) : _start = Stopwatch()..start();

  final String label;
  final Stopwatch _start;

  void stop() {
    _start.stop();
    if (_start.elapsedMilliseconds > 8) {
      // ignore: avoid_print
      print('[perf] $label: ${_start.elapsedMilliseconds}ms');
    }
  }
}

class FramePerf {
  static bool _installed = false;
  static String? _label;
  static int _framesRemaining = 0;
  static Duration _threshold = const Duration(milliseconds: 16);

  static void install({
    Duration slowFrameThreshold = const Duration(milliseconds: 16),
  }) {
    if (_installed) return;
    _installed = true;
    _threshold = slowFrameThreshold;

    SchedulerBinding.instance.addTimingsCallback((timings) {
      final label = _label;
      final watchingInteraction = _framesRemaining > 0;

      for (final timing in timings) {
        final slow = timing.totalSpan >= _threshold;
        if (!watchingInteraction && !slow) continue;

        // ignore: avoid_print
        print(
          '[frame] ${label ?? 'idle'} '
          'total=${_ms(timing.totalSpan)}ms '
          'build=${_ms(timing.buildDuration)}ms '
          'raster=${_ms(timing.rasterDuration)}ms '
          'vsync=${_ms(timing.vsyncOverhead)}ms',
        );
      }

      if (_framesRemaining > 0) {
        _framesRemaining -= timings.length;
        if (_framesRemaining <= 0) {
          _framesRemaining = 0;
          _label = null;
        }
      }
    });
  }

  static void mark(String label, {int frameCount = 8}) {
    _label = label;
    _framesRemaining = frameCount;
    // ignore: avoid_print
    print('[perf] mark $label');
  }

  static String _ms(Duration duration) {
    return (duration.inMicroseconds / 1000).toStringAsFixed(1);
  }
}

class BuildPerf extends StatelessWidget {
  const BuildPerf({required this.label, required this.builder, super.key});

  final String label;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return trackSync('build $label', () => builder(context));
  }
}

class PipelinePerf extends SingleChildRenderObjectWidget {
  const PipelinePerf({required this.label, super.child, super.key});

  final String label;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPipelinePerf(label);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPipelinePerf).label = label;
  }
}

class _RenderPipelinePerf extends RenderProxyBox {
  _RenderPipelinePerf(this.label);

  String label;

  @override
  void performLayout() {
    final sw = Stopwatch()..start();
    super.performLayout();
    sw.stop();
    if (sw.elapsedMilliseconds > 8) {
      // ignore: avoid_print
      print('[perf] layout $label: ${sw.elapsedMilliseconds}ms');
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final sw = Stopwatch()..start();
    super.paint(context, offset);
    sw.stop();
    if (sw.elapsedMilliseconds > 8) {
      // ignore: avoid_print
      print('[perf] paint $label: ${sw.elapsedMilliseconds}ms');
    }
  }
}
