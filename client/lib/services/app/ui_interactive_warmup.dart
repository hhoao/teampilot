import 'dart:io' show Platform;
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_fonts.dart';
import '../../utils/yield_ui_frame.dart';
import '../../widgets/warmup_glyphs.g.dart';

/// Heavy UI-thread work that used to run in [UiWarmup] right after the boot
/// gate — it blocked clicks for ~1s. Runs during [AppDataBootstrap] instead.
abstract final class UiInteractiveWarmup {
  UiInteractiveWarmup._();

  /// Max shaping work per frame so the boot spinner can tick between slices.
  static const _glyphBudgetMs = bootFrameBudgetMs;
  static const _glyphChunkSize = 64;

  static Future<void> run() async {
    if (_inTest) return;

    try {
      await GoogleFonts.pendingFonts([
        GoogleFonts.notoSansSc(fontWeight: FontWeight.w300),
        GoogleFonts.notoSansSc(fontWeight: FontWeight.w400),
        GoogleFonts.notoSansSc(fontWeight: FontWeight.w500),
        GoogleFonts.notoSansSc(fontWeight: FontWeight.w600),
        GoogleFonts.notoSansSc(fontWeight: FontWeight.w700),
        GoogleFonts.notoSansSc(fontWeight: FontWeight.w800),
      ]);
    } on Object {
      // Missing bundled weights: see tool/sync_bundled_google_fonts.dart.
    }

    await _warmGlyphs();
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

  static Future<void> _warmGlyphs() async {
    for (final weight in FontWeight.values) {
      await _shapeWarmupGlyphs(GoogleFonts.notoSansSc(fontWeight: weight));
    }
    // File-tree paths, source-control file lists, and the code/log viewers
    // render in the monospace family with its own CJK fallback chain — none of
    // which the Noto Sans SC passes above touch. Without warming it, the first
    // file-tree / git-panel layout on a tab switch pays the cold mono shaping
    // and fallback-typeface load on the UI thread, which a DevTools trace
    // showed dominating the multi-hundred-ms LAYOUT phase of that frame.
    await _shapeWarmupGlyphs(
      const TextStyle(fontFamily: AppFonts.monoFamily).copyWith(
        fontFamilyFallback: AppFonts.monoFamilyFallback,
      ),
    );
  }

  /// Lays out [warmupGlyphs] in [style] in chunks, yielding a frame between
  /// chunks so the boot spinner keeps ticking. Pre-populates the shaping +
  /// glyph caches for that font so the first real render does not pay them.
  static Future<void> _shapeWarmupGlyphs(TextStyle style) async {
    var offset = 0;
    while (offset < warmupGlyphs.length) {
      final budget = Stopwatch()..start();
      while (offset < warmupGlyphs.length &&
          budget.elapsedMilliseconds < _glyphBudgetMs) {
        final end = min(offset + _glyphChunkSize, warmupGlyphs.length);
        final chunk = warmupGlyphs.substring(offset, end);
        final painter = TextPainter(
          text: TextSpan(text: chunk, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 1200);
        painter.dispose();
        offset = end;
      }
      await yieldUiFrame();
    }
  }

  static Future<void> _warmTerminalEngine() async {
    await yieldUiFrame();
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
