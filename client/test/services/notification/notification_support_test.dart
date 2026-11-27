import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/notification/notification_support.dart';

void main() {
  test('non-Windows hosts support OS notifications', () {
    expect(detectOsNotificationSupport(isWindows: false), isTrue);
  });

  test('a real Windows host supports OS notifications', () {
    expect(
      detectOsNotificationSupport(isWindows: true, isWinePrefix: false),
      isTrue,
    );
  });

  test('a Windows build hosted by Wine has no notification backend', () {
    expect(
      detectOsNotificationSupport(isWindows: true, isWinePrefix: true),
      isFalse,
    );
  });
}
