import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/notification/background_attention_service.dart';

void main() {
  const channel = MethodChannel(BackgroundAttentionService.channelName);

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('forwards enable and disable to the native keeper', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    final service = BackgroundAttentionService(isAndroid: true);
    await service.setEnabled(true);
    await service.setEnabled(false);

    expect(calls, hasLength(2));
    expect(calls[0].method, 'setAttentionKeeperEnabled');
    expect(calls[0].arguments, {'enabled': true});
    expect(calls[1].arguments, {'enabled': false});
  });

  test('does not repeat an unchanged state', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls++;
          return null;
        });

    final service = BackgroundAttentionService(isAndroid: true);
    await service.setEnabled(true);
    await service.setEnabled(true);

    expect(calls, 1);
  });

  test('does nothing on non-Android without calling the channel', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          called = true;
          return null;
        });

    final service = BackgroundAttentionService(isAndroid: false);
    await service.setEnabled(true);

    expect(called, isFalse);
  });

  test('swallows native failures and retries later', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls++;
          throw PlatformException(code: 'unavailable');
        });

    final service = BackgroundAttentionService(isAndroid: true);
    await service.setEnabled(true);
    await service.setEnabled(true);

    expect(calls, 2);
  });
}
