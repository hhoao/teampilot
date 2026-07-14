import 'dart:convert';

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

  /// Test/diagnostics: how many probe calls were short-circuited.
  static int bypassHitCount = 0;

  /// Test/diagnostics: probe-shaped calls that fell through to the platform.
  static int bypassMissCount = 0;

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
    if (bypass != null) {
      bypassHitCount += 1;
      assert(() {
        if (bypassHitCount <= 6) {
          debugPrint(
            'Teampilot probe bypass HIT #$bypassHitCount channel=$channel',
          );
        }
        return true;
      }());
      return bypass;
    }
    if (_looksLikeProbe(channel, message)) {
      bypassMissCount += 1;
      assert(() {
        if (bypassMissCount <= 6) {
          debugPrint(
            'Teampilot probe bypass MISS #$bypassMissCount '
            'channel=$channel preview=${_utf8Preview(message)}',
          );
        }
        return true;
      }());
    }
    return _delegate.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    _delegate.setMessageHandler(channel, handler);
  }

  Future<ByteData?>? _maybeBypass(String channel, ByteData? message) {
    if (message == null) return null;

    // Prefer raw payload scan — survives codec/offset quirks that break decode.
    final preview = _utf8Preview(message);

    // SynchronousFuture: ProfiledBinaryMessenger uses `await proxy.send(...)`.
    // Future.value only resumes on a microtask, so Timeline "Platform Channel
    // send" slices inflate to the rest of the surrounding sync build/layout
    // (seen as ~650 ms Clipboard/LiveText/ProcessText in DevTools even when
    // the platform was never contacted). Sync completion keeps those honest.
    if (channel == _platformChannel) {
      if (preview.contains('Clipboard.hasStrings')) {
        return SynchronousFuture<ByteData?>(
          _jsonCodec.encodeSuccessEnvelope(<String, Object?>{'value': true}),
        );
      }
      if (preview.contains('LiveText.isLiveTextInputAvailable')) {
        return SynchronousFuture<ByteData?>(
          _jsonCodec.encodeSuccessEnvelope(false),
        );
      }
    }

    if (channel == _processTextChannel &&
        preview.contains('ProcessText.queryTextActions')) {
      return SynchronousFuture<ByteData?>(
        _standardCodec.encodeSuccessEnvelope(<Object?, Object?>{}),
      );
    }

    return null;
  }

  static bool _looksLikeProbe(String channel, ByteData? message) {
    if (message == null) return false;
    if (channel != _platformChannel && channel != _processTextChannel) {
      return false;
    }
    final preview = _utf8Preview(message);
    return preview.contains('Clipboard.hasStrings') ||
        preview.contains('LiveText.isLiveTextInputAvailable') ||
        preview.contains('ProcessText.queryTextActions');
  }

  static String _utf8Preview(ByteData? message) {
    if (message == null) return '';
    final bytes = message.buffer.asUint8List(
      message.offsetInBytes,
      message.lengthInBytes,
    );
    return utf8.decode(bytes, allowMalformed: true);
  }
}
