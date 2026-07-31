import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/termux/termux_package_probe.dart';

void main() {
  const channel = MethodChannel('com.hhoa.teampilot/packages');

  TestWidgetsFlutterBinding.ensureInitialized();

  group('TermuxPackageProbe', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns false on non-Android without calling channel', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        called = true;
        return true;
      });

      final probe = TermuxPackageProbe(isAndroid: false);
      expect(await probe.isTermuxInstalled(), isFalse);
      expect(called, isFalse);
    });

    test('returns true when channel reports Termux installed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isPackageInstalled');
        expect(call.arguments, {'packageName': 'com.termux'});
        return true;
      });

      final probe = TermuxPackageProbe(isAndroid: true);
      expect(await probe.isTermuxInstalled(), isTrue);
    });

    test('returns false when channel reports Termux missing', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => false);

      final probe = TermuxPackageProbe(isAndroid: true);
      expect(await probe.isTermuxInstalled(), isFalse);
    });

    test('returns false when channel returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      final probe = TermuxPackageProbe(isAndroid: true);
      expect(await probe.isTermuxInstalled(), isFalse);
    });

    test('returns false when channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'error');
      });

      final probe = TermuxPackageProbe(isAndroid: true);
      expect(await probe.isTermuxInstalled(), isFalse);
    });

    test('uses injected MethodChannel instance', () async {
      const injected = MethodChannel('com.hhoa.teampilot/packages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(injected, (_) async => true);

      final probe = TermuxPackageProbe(channel: injected, isAndroid: true);
      expect(await probe.isTermuxInstalled(), isTrue);
    });
  });
}
