import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';
import 'package:teampilot/services/terminal/fullscreen_reinject_guard.dart';

void main() {
  group('shouldSkipReinjectAfterCrStuck', () {
    test('regionMovedDown skips only when empty and needle visible', () {
      expect(
        shouldSkipReinjectAfterCrStuck(
          semantics: ComposerSubmitSemantics.regionMovedDown,
          composerRegionEmpty: true,
          needleStillVisible: true,
        ),
        isTrue,
      );
    });

    for (final case_ in [
      (empty: false, needle: true),
      (empty: true, needle: false),
      (empty: false, needle: false),
    ]) {
      test(
        'regionMovedDown does not skip empty=${case_.empty} '
        'needle=${case_.needle}',
        () {
          expect(
            shouldSkipReinjectAfterCrStuck(
              semantics: ComposerSubmitSemantics.regionMovedDown,
              composerRegionEmpty: case_.empty,
              needleStillVisible: case_.needle,
            ),
            isFalse,
          );
        },
      );
    }

    for (final semantics in [
      ComposerSubmitSemantics.regionCleared,
      ComposerSubmitSemantics.timed,
    ]) {
      test('$semantics never skips even when empty+needle', () {
        expect(
          shouldSkipReinjectAfterCrStuck(
            semantics: semantics,
            composerRegionEmpty: true,
            needleStillVisible: true,
          ),
          isFalse,
        );
      });
    }
  });
}
