import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';
import 'package:teampilot/theme/installed_font_enumerator.dart';

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

  test('linux system mono is Latin-first with SC before monospace', () {
    final r = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.linux,
    );
    // Latin primary (Orca / VS Code style) — not CJK mono, which sparsifies ASCII.
    expect(r.monoFamily, 'DejaVu Sans Mono');
    expect(r.monoFallback.contains('monospace'), isTrue);
    final chain = [r.monoFamily, ...r.monoFallback];
    final monoIdx = chain.indexOf('monospace');
    final scIdx = chain.indexOf('Noto Sans Mono CJK SC');
    expect(scIdx, greaterThanOrEqualTo(0));
    expect(scIdx, lessThan(monoIdx));
  });

  test('android system mono is Latin-first with SC before monospace', () {
    final r = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.android,
    );
    expect(r.monoFamily, 'Droid Sans Mono');
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

  test('UI and mono fallbacks include platform color emoji fonts', () {
    final linux = AppFontResolver.resolve(
      uiFontId: 'notoSansSc',
      monoFontId: 'jetbrainsMono',
      platform: TargetPlatform.linux,
    );
    // Bundled / FontLoader family (not fontconfig "Noto Color Emoji").
    expect(linux.uiFallback, contains('NotoColorEmoji'));
    expect(linux.monoFallback, contains('NotoColorEmoji'));
    expect(
      linux.uiFallback.indexOf('NotoColorEmoji'),
      lessThan(linux.uiFallback.indexOf('sans-serif')),
    );

    final mac = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.macOS,
    );
    expect(mac.uiFallback, contains('Apple Color Emoji'));
    expect(mac.monoFallback, contains('Apple Color Emoji'));

    final win = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.windows,
    );
    expect(win.uiFallback, contains('Segoe UI Emoji'));
    expect(win.monoFallback, contains('Segoe UI Emoji'));

    final android = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.android,
    );
    expect(android.uiFallback, contains('NotoColorEmoji'));
    expect(android.monoFallback, contains('NotoColorEmoji'));
  });

  test('installed ids resolve to family key without collapsing to system', () {
    InstalledFontEnumerator.clearCache();
    final r = AppFontResolver.resolve(
      uiFontId: 'installed:DejaVuSans',
      monoFontId: 'installed:DejaVuSansMono',
      platform: TargetPlatform.linux,
    );
    expect(r.resolvedUiId, 'installed:DejaVuSans');
    expect(r.resolvedMonoId, 'installed:DejaVuSansMono');
    expect(r.uiFamily, 'DejaVuSans');
    expect(r.monoFamily, 'DejaVuSansMono');
    // Before listFamilies(), enumerator reports non-fontconfig → may need load.
    expect(r.uiNeedsBundledLoad, isFalse);
    expect(r.monoNeedsBundledLoad, isFalse);
  });
}
