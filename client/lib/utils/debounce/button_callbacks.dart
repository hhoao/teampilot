import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'throttles.dart';

const kDefaultButtonThrottle = Duration(milliseconds: 500);
const kNavigationThrottle = Duration(milliseconds: 300);

bool get _throttleInTests =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Sync button handler: first tap runs, repeats ignored until [duration] elapses.
VoidCallback throttledOnPressed(
  String tag,
  VoidCallback onPressed, {
  Duration duration = kDefaultButtonThrottle,
}) {
  if (_throttleInTests) return onPressed;
  return () {
    Throttles.throttle(tag, duration, onPressed);
  };
}

/// Same for [GestureDetector.onTap] / [InkWell.onTap].
VoidCallback throttledTap(
  String tag,
  VoidCallback onTap, {
  Duration duration = kNavigationThrottle,
}) {
  return throttledOnPressed(tag, onTap, duration: duration);
}

/// Async handler: throttle only gates *starting* another invocation.
VoidCallback throttledAsync(
  String tag,
  Future<void> Function() action, {
  Duration duration = kDefaultButtonThrottle,
}) {
  if (_throttleInTests) {
    return () {
      unawaited(action());
    };
  }
  return () {
    Throttles.throttle(tag, duration, () {
      unawaited(action());
    });
  };
}
