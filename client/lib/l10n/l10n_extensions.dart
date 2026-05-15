// Hand-maintained extensions for generated [AppLocalizations].
// Edit app_en.arb / app_zh.arb, then flutter pub get or flutter run (generate: true).

import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

extension AppLocalizationsX on AppLocalizations {
  /// Display name for a [LayoutPreferences.themeColorPreset] id.
  String themeColorPresetName(String id) {
    switch (id) {
      case 'ocean':
        return themePresetOcean;
      case 'violet':
        return themePresetViolet;
      case 'amber':
        return themePresetAmber;
      case 'forest':
        return themePresetForest;
      case 'graphite':
      default:
        return themePresetGraphite;
    }
  }

  String providerListCaption(int modelCount, bool proxyEnabled) {
    final countPart = providerListModelCount(modelCount);
    final proxyPart = proxyEnabled ? proxyOnShort : proxyOffShort;
    return '$countPart · $proxyPart';
  }
}

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
