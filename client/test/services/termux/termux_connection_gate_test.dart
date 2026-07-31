import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/termux/termux_connection_gate.dart';

void main() {
  group('allowTermuxWorkOps', () {
    test('allows non-termux home regardless of connection', () {
      expect(
        allowTermuxWorkOps(isTermuxHome: false, connected: false),
        isTrue,
      );
      expect(
        allowTermuxWorkOps(isTermuxHome: false, connected: true),
        isTrue,
      );
    });

    test('blocks termux home when disconnected', () {
      expect(
        allowTermuxWorkOps(isTermuxHome: true, connected: false),
        isFalse,
      );
    });

    test('allows termux home when connected', () {
      expect(
        allowTermuxWorkOps(isTermuxHome: true, connected: true),
        isTrue,
      );
    });
  });

  group('termuxWorkOpsBlockMessage', () {
    const message = 'blocked';

    test('returns message for termux target when disconnected', () {
      expect(
        termuxWorkOpsBlockMessage(
          target: RuntimeTarget.termux(),
          home: RuntimeTarget.local(),
          termuxConnected: false,
          message: message,
        ),
        message,
      );
    });

    test('returns null for termux target when connected', () {
      expect(
        termuxWorkOpsBlockMessage(
          target: RuntimeTarget.termux(),
          home: RuntimeTarget.local(),
          termuxConnected: true,
          message: message,
        ),
        isNull,
        );
    });

    test('returns message when home is termux and disconnected', () {
      expect(
        termuxWorkOpsBlockMessage(
          target: RuntimeTarget.local(),
          home: RuntimeTarget.termux(),
          termuxConnected: false,
          message: message,
        ),
        message,
      );
    });
  });
}
