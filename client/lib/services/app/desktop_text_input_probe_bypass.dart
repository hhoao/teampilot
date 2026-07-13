import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether desktop EditableText mount probes should be short-circuited.
///
/// Linux GTK implements [Clipboard.hasStrings] by reading the full clipboard
/// text; LiveText / ProcessText are mobile-only but still queried on every
/// [EditableText] init. Web already bypasses clipboard probing in framework.
bool shouldInstallDesktopTextInputProbeBypass({
  required bool isWeb,
  required bool isAndroid,
  required bool isIOS,
  required bool isLinux,
  required bool isWindows,
  required bool isMacOS,
}) {
  if (isWeb || isAndroid || isIOS) return false;
  return isLinux || isWindows || isMacOS;
}

/// Wraps the engine [BinaryMessenger] and answers EditableText mount probes
/// locally so the UI isolate does not block on platform round-trips.
class DesktopTextInputProbeBypassMessenger extends BinaryMessenger {
  DesktopTextInputProbeBypassMessenger(this._delegate);

  final BinaryMessenger _delegate;

  static const _platformChannel = 'flutter/platform';
  static const _processTextChannel = 'flutter/processtext';

  static const _jsonCodec = JSONMethodCodec();
  static const _standardCodec = StandardMethodCodec();

  @override
  // ignore: deprecated_member_use
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) {
    // ignore: deprecated_member_use
    return _delegate.handlePlatformMessage(channel, data, callback);
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    final bypass = _maybeBypass(channel, message);
    if (bypass != null) return bypass;
    return _delegate.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    _delegate.setMessageHandler(channel, handler);
  }

  Future<ByteData?>? _maybeBypass(String channel, ByteData? message) {
    if (message == null) return null;

    if (channel == _platformChannel) {
      final MethodCall call;
      try {
        call = _jsonCodec.decodeMethodCall(message);
      } on FormatException {
        return null;
      }
      switch (call.method) {
        case 'Clipboard.hasStrings':
          // Match web: always treat as pasteable; avoid GTK full-text read.
          return Future<ByteData?>.value(
            _jsonCodec.encodeSuccessEnvelope(<String, Object?>{'value': true}),
          );
        case 'LiveText.isLiveTextInputAvailable':
          return Future<ByteData?>.value(
            _jsonCodec.encodeSuccessEnvelope(false),
          );
        default:
          return null;
      }
    }

    if (channel == _processTextChannel) {
      final MethodCall call;
      try {
        call = _standardCodec.decodeMethodCall(message);
      } on FormatException {
        return null;
      }
      if (call.method == 'ProcessText.queryTextActions') {
        return Future<ByteData?>.value(
          _standardCodec.encodeSuccessEnvelope(<Object?, Object?>{}),
        );
      }
    }

    return null;
  }
}
