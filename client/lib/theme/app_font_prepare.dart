import 'package:flutter/painting.dart';

import 'app_font_loader.dart';
import 'app_font_resolver.dart';
import 'font_catalog.dart';
import 'installed_font_enumerator.dart';

/// Ensures installed-font metadata is ready, loads file-backed faces if needed,
/// and warms Skia/HarfBuzz for the resolved families before first paint.
Future<void> prepareFontsForUse(ResolvedFonts fonts) async {
  if (isInstalledFontId(fonts.resolvedUiId) ||
      isInstalledFontId(fonts.resolvedMonoId)) {
    await InstalledFontEnumerator.listFamilies();
  }

  // Re-resolve so needsInstalledLoad reflects fontconfig vs basename mode.
  final resolved = AppFontResolver.resolve(
    uiFontId: fonts.resolvedUiId,
    monoFontId: fonts.resolvedMonoId,
  );
  await loadFontsFor(resolved);
  await warmFontFamilies([
    resolved.uiFamily,
    resolved.monoFamily,
  ]);
}

/// Shapes a small Latin+CJK sample so face construction happens off the
/// full-app layout path.
Future<void> warmFontFamilies(Iterable<String> families) async {
  // Yield so any pending microtasks (e.g. dropdown close) can settle first.
  await Future<void>.delayed(Duration.zero);
  for (final family in families) {
    if (family.isEmpty) continue;
    try {
      final painter = TextPainter(
        text: TextSpan(
          text: '加载中 Aa1',
          style: TextStyle(fontFamily: family, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.dispose();
    } on Object {
      // Missing faces fall through to fallbacks at paint time.
    }
  }
}
