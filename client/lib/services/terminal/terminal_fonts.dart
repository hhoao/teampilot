import 'package:flutter/services.dart';
import 'package:teampilot/utils/logger.dart';

/// Active terminal font ([TerminalStyle.fontFamily]).
const kTerminalFontFamily = 'JetBrainsMono NFM';

/// Bundled alternate; listed in [TerminalStyle.fontFamilyFallback].
const kUbuntuSansMonoFontFamily = 'Ubuntu Sans Mono';

/// Loads terminal fonts from [assets/fonts/terminal/] (see sync script).
///
/// JetBrainsMono NFM is the default face. Ubuntu Sans Mono is preloaded for
/// fallback / future switching (change [kTerminalFontFamily] + Regular asset).
Future<void> _loadFontAsset(FontLoader loader, String assetPath) async {
  try {
    loader.addFont(rootBundle.load(assetPath));
    await loader.load();
  } on Object {
    appLogger.w('Failed to load font asset: $assetPath');
  }
}

Future<void> loadBundledTerminalFonts() async {
  await _loadFontAsset(
    FontLoader(kTerminalFontFamily),
    'assets/fonts/terminal/JetBrainsMonoNerdFontMono-Regular.ttf',
  );

  final ubuntu = FontLoader(kUbuntuSansMonoFontFamily);
  var hasUbuntuFont = false;
  for (final asset in const [
    'assets/fonts/terminal/UbuntuSansMono-Regular.ttf',
    'assets/fonts/terminal/UbuntuSansMono-Bold.ttf',
  ]) {
    try {
      ubuntu.addFont(rootBundle.load(asset));
      hasUbuntuFont = true;
    } on Object {
      appLogger.w('Failed to load Ubuntu font asset: $asset');
    }
  }
  if (!hasUbuntuFont) return;
  try {
    await ubuntu.load();
  } on Object {
    // No Ubuntu files in bundle; terminal uses JetBrains or system monospace.
  }
}
