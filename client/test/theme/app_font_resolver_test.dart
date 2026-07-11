import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';

void main() {
  test('unknown ids normalize to system', () {
    final r = AppFontResolver.resolve(
      uiFontId: 'x',
      monoFontId: 'y',
      platform: TargetPlatform.linux,
    );
    expect(r.resolvedUiId, 'system');
    expect(r.resolvedMonoId, 'system');
  });

  test('linux system mono puts SC before monospace', () {
    final r = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.linux,
    );
    expect(r.monoFamily, isNot('monospace'));
    expect(r.monoFallback.contains('monospace'), isTrue);
    // primary itself should be SC-capable, or SC appears before monospace in chain
    final chain = [r.monoFamily, ...r.monoFallback];
    final monoIdx = chain.indexOf('monospace');
    final scIdx = chain.indexOf('Noto Sans Mono CJK SC');
    expect(scIdx, greaterThanOrEqualTo(0));
    expect(scIdx, lessThan(monoIdx));
  });

  test('bundled mono resolves JetBrains family', () {
    final r = AppFontResolver.resolve(
      uiFontId: 'notoSansSc',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    expect(r.monoFamily, 'JetBrainsMono NFM');
    expect(r.monoNeedsBundledLoad, isTrue);
    expect(r.uiNeedsBundledLoad, isTrue);
  });

  test('system needs no bundled load flags', () {
    final r = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.android,
    );
    expect(r.uiNeedsBundledLoad, isFalse);
    // silent Ubuntu fallback load may still set a softer flag — if implemented
    // as optional asset warm, document in loader tests; resolver flag for
    // *primary* bundled should be false.
    expect(r.monoNeedsBundledLoad, isFalse);
  });

  test('macOS and Windows system primaries are platform-native', () {
    final mac = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.macOS,
    );
    expect(mac.uiFamily, anyOf('PingFang SC', '.AppleSystemUIFont'));
    expect(mac.monoFamily, 'Menlo');

    final win = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.windows,
    );
    expect(win.uiFamily, 'Segoe UI');
    expect(win.monoFamily, 'Consolas');
  });
}
