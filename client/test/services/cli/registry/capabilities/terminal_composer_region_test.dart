import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/terminal_composer_region.dart';

void main() {
  test('default spec is regionCleared with empty prefix/border', () {
    expect(fullscreenDefaultComposerSpec.submitSemantics,
        ComposerSubmitSemantics.regionCleared);
    expect(fullscreenDefaultComposerSpec.prefixes, isEmpty);
    expect(fullscreenDefaultComposerSpec.border.left, isEmpty);
    expect(fullscreenDefaultComposerSpec.border.bottom, isEmpty);
    expect(fullscreenDefaultComposerSpec.border.corner, isEmpty);
  });

  test('opencode box spec carries border candidates', () {
    const spec = FullscreenComposerRegionSpec(
      submitSemantics: ComposerSubmitSemantics.regionCleared,
      prefixes: ['\u2503'],
      border: ComposerBorderSpec(
        left: ['\u2503', '\u2502'],
        bottom: ['\u2580', '\u2500'],
        corner: ['\u2579', '\u2570', '\u2514'],
      ),
    );
    expect(spec.prefixes, ['\u2503']);
    expect(spec.border.left, ['\u2503', '\u2502']);
  });

  test('timed spec keeps semantics only', () {
    expect(fullscreenTimedComposerSpec.submitSemantics,
        ComposerSubmitSemantics.timed);
  });
}
