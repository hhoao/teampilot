import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/app/desktop_text_input_probe_bypass.dart';

void main() {
  group('DesktopTextInputProbeBypassMessenger', () {
    late _RecordingMessenger delegate;
    late DesktopTextInputProbeBypassMessenger messenger;

    setUp(() {
      DesktopTextInputProbeBypassMessenger.bypassHitCount = 0;
      DesktopTextInputProbeBypassMessenger.bypassMissCount = 0;
      delegate = _RecordingMessenger();
      messenger = DesktopTextInputProbeBypassMessenger(delegate);
    });

    test('short-circuits Clipboard.hasStrings without hitting platform', () async {
      const codec = JSONMethodCodec();
      final call = codec.encodeMethodCall(
        const MethodCall('Clipboard.hasStrings', 'text/plain'),
      );

      final future = messenger.send('flutter/platform', call);
      expect(future, isA<SynchronousFuture<ByteData?>>());
      final reply = await future;

      expect(delegate.sent, isEmpty);
      expect(codec.decodeEnvelope(reply!), <String, Object?>{'value': true});
      expect(DesktopTextInputProbeBypassMessenger.bypassHitCount, greaterThan(0));
    });

    test('short-circuits LiveText.isLiveTextInputAvailable', () async {
      const codec = JSONMethodCodec();
      final call = codec.encodeMethodCall(
        const MethodCall('LiveText.isLiveTextInputAvailable'),
      );

      final reply = await messenger.send('flutter/platform', call);

      expect(delegate.sent, isEmpty);
      expect(codec.decodeEnvelope(reply!), isFalse);
    });

    test('short-circuits ProcessText.queryTextActions', () async {
      const codec = StandardMethodCodec();
      final call = codec.encodeMethodCall(
        const MethodCall('ProcessText.queryTextActions'),
      );

      final reply = await messenger.send('flutter/processtext', call);

      expect(delegate.sent, isEmpty);
      expect(codec.decodeEnvelope(reply!), <Object?, Object?>{});
    });

    test('forwards Clipboard.getData to the platform', () async {
      const codec = JSONMethodCodec();
      final call = codec.encodeMethodCall(
        const MethodCall('Clipboard.getData', 'text/plain'),
      );
      final expected = codec.encodeSuccessEnvelope(
        <String, Object?>{'text': 'hi'},
      );
      delegate.nextReply = expected;

      final reply = await messenger.send('flutter/platform', call);

      expect(delegate.sent, hasLength(1));
      expect(delegate.sent.single.channel, 'flutter/platform');
      expect(reply, same(expected));
    });

    test('forwards unrelated platform methods', () async {
      const codec = JSONMethodCodec();
      final call = codec.encodeMethodCall(
        const MethodCall('SystemSound.play', 'SystemSoundType.click'),
      );
      final expected = codec.encodeSuccessEnvelope(null);
      delegate.nextReply = expected;

      final reply = await messenger.send('flutter/platform', call);

      expect(delegate.sent, hasLength(1));
      expect(reply, same(expected));
    });
  });

  group('shouldInstallDesktopTextInputProbeBypass', () {
    test('is true for linux/windows/macos when not web', () {
      expect(
        shouldInstallDesktopTextInputProbeBypass(
          isWeb: false,
          isAndroid: false,
          isIOS: false,
          isLinux: true,
          isWindows: false,
          isMacOS: false,
        ),
        isTrue,
      );
      expect(
        shouldInstallDesktopTextInputProbeBypass(
          isWeb: false,
          isAndroid: false,
          isIOS: false,
          isLinux: false,
          isWindows: true,
          isMacOS: false,
        ),
        isTrue,
      );
    });

    test('is false for web/android/ios', () {
      expect(
        shouldInstallDesktopTextInputProbeBypass(
          isWeb: true,
          isAndroid: false,
          isIOS: false,
          isLinux: false,
          isWindows: false,
          isMacOS: false,
        ),
        isFalse,
      );
      expect(
        shouldInstallDesktopTextInputProbeBypass(
          isWeb: false,
          isAndroid: true,
          isIOS: false,
          isLinux: false,
          isWindows: false,
          isMacOS: false,
        ),
        isFalse,
      );
    });
  });
}

class _RecordingMessenger extends BinaryMessenger {
  final sent = <({String channel, ByteData? message})>[];
  ByteData? nextReply;

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {
    callback?.call(null);
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) async {
    sent.add((channel: channel, message: message));
    return nextReply;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}
}
