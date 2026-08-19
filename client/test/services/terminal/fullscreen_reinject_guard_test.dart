import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/fullscreen_cr_ack_config.dart';
import 'package:teampilot/services/terminal/fullscreen_reinject_guard.dart';

void main() {
  group('shouldSkipReinjectAfterCrStuck', () {
    test('composerMovesDown skips only when empty, needle visible, not staged', () {
      expect(
        shouldSkipReinjectAfterCrStuck(
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          composerChromeEmpty: true,
          needleStillVisible: true,
        ),
        isTrue,
      );
    });

    test('composerMovesDown does not skip when needle still staged in composer', () {
      expect(
        shouldSkipReinjectAfterCrStuck(
          strategy: FullscreenCrAckStrategy.composerMovesDown,
          composerChromeEmpty: true,
          needleStillVisible: true,
          needleStagedInComposer: true,
        ),
        isFalse,
      );
    });

    for (final case_ in [
      (empty: false, needle: true),
      (empty: true, needle: false),
      (empty: false, needle: false),
    ]) {
      test(
        'composerMovesDown does not skip empty=${case_.empty} '
        'needle=${case_.needle}',
        () {
          expect(
            shouldSkipReinjectAfterCrStuck(
              strategy: FullscreenCrAckStrategy.composerMovesDown,
              composerChromeEmpty: case_.empty,
              needleStillVisible: case_.needle,
            ),
            isFalse,
          );
        },
      );
    }

    for (final strategy in [
      FullscreenCrAckStrategy.anchorCellClears,
      FullscreenCrAckStrategy.timed,
    ]) {
      test('$strategy never skips even when empty+needle', () {
        expect(
          shouldSkipReinjectAfterCrStuck(
            strategy: strategy,
            composerChromeEmpty: true,
            needleStillVisible: true,
          ),
          isFalse,
        );
      });
    }
  });
}
