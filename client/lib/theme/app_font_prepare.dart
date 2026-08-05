import 'app_font_loader.dart';
import 'app_font_resolver.dart';
import 'font_catalog.dart';
import 'installed_font_enumerator.dart';

/// Ensures installed-font metadata is ready and loads file-backed faces if
/// needed before first paint.
///
/// FontLoader registration here is what makes runtime font resolution hit the
/// registry instead of scanning fontconfig per paragraph — the actual fix for
/// the terminal-open stall. Off-screen TextPainter warmup was removed: it does
/// not persist across paragraphs.
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
}
