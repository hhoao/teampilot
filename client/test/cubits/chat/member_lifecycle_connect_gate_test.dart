import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/member_lifecycle_connect_gate.dart';

void main() {
  group('lifecycle gate reason helpers', () {
    test('manifest bus overlay use per-member retry', () {
      for (final reason in ['manifest', 'bus', 'overlay']) {
        expect(lifecycleGateReasonNeedsMemberRetry(reason), isTrue);
        expect(lifecycleGateReasonIsTransient(reason), isTrue);
      }
    });

    test('auth is not transient', () {
      expect(lifecycleGateReasonIsTransient('auth'), isFalse);
      expect(lifecycleGateReasonNeedsMemberRetry('auth'), isFalse);
    });
  });
}
