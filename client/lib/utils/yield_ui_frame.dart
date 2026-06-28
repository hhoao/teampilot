import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Yields after the next frame is **scheduled and painted** so boot animations
/// (see [WallClockBootSpinner]) get a chance to update.
Future<void> yieldUiFrame() {
  final binding = SchedulerBinding.instance;
  final completer = Completer<void>();
  binding.addPostFrameCallback((_) {
    if (!completer.isCompleted) completer.complete();
  });
  binding.scheduleFrame();
  return completer.future;
}

/// Default per-frame CPU budget for cooperative boot tasks on the UI isolate.
const bootFrameBudgetMs = 4;
