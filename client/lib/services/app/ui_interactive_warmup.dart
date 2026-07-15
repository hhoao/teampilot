import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/layout_preferences.dart';
import '../../theme/app_font_resolver.dart';
import '../../theme/app_text_styles_warmup.dart';
import '../../theme/font_catalog.dart';
import '../../utils/logger.dart';
import '../../utils/yield_ui_frame.dart';
import '../../widgets/warmup_glyphs.g.dart';

/// Heavy UI-thread work during [AppDataBootstrap] — fonts, glyph shaping, and
/// terminal engine.
abstract final class UiInteractiveWarmup {
  UiInteractiveWarmup._();

  static Future<void> run({LayoutPreferences? layoutPreferences}) async {
    if (_inTest) return;

    final fonts = AppFontResolver.resolve(
      uiFontId: layoutPreferences?.uiFontId ?? FontCatalog.defaultUiId,
      monoFontId: layoutPreferences?.monoFontId ?? FontCatalog.defaultMonoId,
    );
    if (fonts.uiNeedsBundledLoad) {
      try {
        await GoogleFonts.pendingFonts([
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w400),
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w500),
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w600),
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w700),
          GoogleFonts.notoSansSc(fontWeight: FontWeight.w800),
        ]);
      } on Object {
        // Missing bundled weights: see tool/sync_bundled_google_fonts.dart.
      }
    }

    await _warmGlyphs(layoutPreferences: layoutPreferences);
    await yieldUiFrame();
    await _warmTerminalEngine();
  }

  static bool get _inTest {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } on Object {
      return false;
    }
  }

  static Future<void> _warmGlyphs({
    LayoutPreferences? layoutPreferences,
  }) async {
    final theme = layoutPreferences == null
        ? bootstrapThemeForTextWarmup()
        : themeForInteractiveWarmup(layoutPreferences);
    final raw = textStylesForThemeWarmup(theme);
    final styles = TpGlyphWarmup.dedupeByShapeKey(raw);
    appLogger.i(
      '[boot] glyph warmup styles ${raw.length}→${styles.length} '
      '(shape fingerprints)',
    );
    final sw = Stopwatch()..start();
    TpGlyphWarmup.shapeAll(styles: styles, glyphs: warmupGlyphs);
    appLogger.i('[boot] glyph warmup shape done +${sw.elapsedMilliseconds}ms');
  }

  /// Lays out the full [warmupGlyphs] string in one pass.
  ///
  /// Boot splash is static, so we do not slice work across frames — cooperative
  /// yields previously dominated wall time without helping perceived smoothness.
  // (shaping delegated to [TpGlyphWarmup])
  static Future<void> _warmTerminalEngine() async {
    final engine = TerminalEngine(
      config: TerminalConfig.defaults().copyWith(
        scrolling: TerminalConfig.defaults().scrolling.copyWith(history: 100),
      ),
    );
    try {
      engine.resize(columns: 80, rows: 24);
      engine.feed(Uint8List.fromList('\n'.codeUnits));
    } finally {
      engine.dispose();
    }
    await yieldUiFrame();
  }
}
