import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/double_shift_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  KeyDownEvent keyDown(
    LogicalKeyboardKey logicalKey, {
    Duration timeStamp = Duration.zero,
  }) => KeyDownEvent(
    physicalKey: switch (logicalKey) {
      LogicalKeyboardKey.shiftLeft => PhysicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight => PhysicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.keyA => PhysicalKeyboardKey.keyA,
      _ => PhysicalKeyboardKey.shiftLeft,
    },
    logicalKey: logicalKey,
    timeStamp: timeStamp,
  );

  group('DoubleShiftDetector', () {
    test('fires on two Shift key-downs within the window', () {
      final detector = DoubleShiftDetector(
        window: const Duration(milliseconds: 400),
      );

      expect(
        detector.feed(keyDown(LogicalKeyboardKey.shiftLeft)),
        isFalse,
      );
      expect(
        detector.feed(
          keyDown(
            LogicalKeyboardKey.shiftLeft,
            timeStamp: const Duration(milliseconds: 200),
          ),
        ),
        isTrue,
      );
    });

    test('does not fire when the second Shift is outside the window', () {
      final detector = DoubleShiftDetector(
        window: const Duration(milliseconds: 400),
      );

      expect(
        detector.feed(keyDown(LogicalKeyboardKey.shiftLeft)),
        isFalse,
      );
      expect(
        detector.feed(
          keyDown(
            LogicalKeyboardKey.shiftRight,
            timeStamp: const Duration(milliseconds: 500),
          ),
        ),
        isFalse,
      );
    });

    test('cancels when another key is pressed between Shifts', () {
      final detector = DoubleShiftDetector(
        window: const Duration(milliseconds: 400),
      );

      expect(
        detector.feed(keyDown(LogicalKeyboardKey.shiftLeft)),
        isFalse,
      );
      expect(
        detector.feed(
          keyDown(
            LogicalKeyboardKey.keyA,
            timeStamp: const Duration(milliseconds: 50),
          ),
        ),
        isFalse,
      );
      expect(
        detector.feed(
          keyDown(
            LogicalKeyboardKey.shiftLeft,
            timeStamp: const Duration(milliseconds: 100),
          ),
        ),
        isFalse,
      );
    });

    test('ignores KeyUp events', () {
      final detector = DoubleShiftDetector();
      expect(
        detector.feed(
          KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.shiftLeft,
            logicalKey: LogicalKeyboardKey.shiftLeft,
            timeStamp: Duration.zero,
          ),
        ),
        isFalse,
      );
    });
  });
}
