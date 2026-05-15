import 'package:flutter/services.dart';

/// Active terminal font ([TerminalStyle.fontFamily]).
const kTerminalFontFamily = 'JetBrainsMono NFM';

/// Bundled alternate; listed in [TerminalStyle.fontFamilyFallback].
const kUbuntuSansMonoFontFamily = 'Ubuntu Sans Mono';

/// Loads terminal fonts from [assets/fonts/terminal/] (see sync script).
///
/// JetBrainsMono NFM is the default face. Ubuntu Sans Mono is preloaded for
/// fallback / future switching (change [kTerminalFontFamily] + Regular asset).
Future<void> loadBundledTerminalFonts() async {
  final jetbrains = FontLoader(kTerminalFontFamily)
    ..addFont(
      rootBundle.load(
        'assets/fonts/terminal/JetBrainsMonoNerdFontMono-Regular.ttf',
      ),
    );
  await jetbrains.load();

  final ubuntu = FontLoader(kUbuntuSansMonoFontFamily)
    ..addFont(
      rootBundle.load('assets/fonts/terminal/UbuntuSansMono-Regular.ttf'),
    )
    ..addFont(
      rootBundle.load('assets/fonts/terminal/UbuntuSansMono-Bold.ttf'),
    );
  await ubuntu.load();
}
