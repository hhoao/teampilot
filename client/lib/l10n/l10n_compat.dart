// Hand-written compat layer for slang-based localization.
//
// Provides gen_l10n-style primitives (`LocalizationsDelegate`, static delegate
// lists, `lookupAppLocalizations`) so tests and pre-bootstrap error pages keep
// their existing wiring, while production code uses slang's TranslationProvider.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'translations.g.dart';
import 'translations_zh.g.dart' show AppLocalizationsZh;

/// Serves [AppLocalizations] through Flutter's `Localizations` mechanism,
/// mirroring gen_l10n's generated delegate. Used by widget tests and error
/// pages that render before/without `TranslationProvider`.
class AppLocalizationsCompatDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsCompatDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'zh';

  @override
  // SynchronousFuture mirrors gen_l10n's generated delegate so `Localizations`
  // builds its subtree within the same frame (tests pump once).
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));

  @override
  bool shouldReload(AppLocalizationsCompatDelegate old) => false;
}

/// gen_l10n-compatible delegate list: our own delegate first, then the
/// framework delegates (Material/Cupertino widgets, text direction).
const appLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  AppLocalizationsCompatDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// gen_l10n-compatible supported locales.
const appLocalizationsSupportedLocales = <Locale>[Locale('en'), Locale('zh')];

/// gen_l10n-compatible lookup function.
AppLocalizations lookupAppLocalizations(Locale locale) {
  return locale.languageCode == 'zh'
      ? AppLocalizationsZh()
      : AppLocalizationsEn();
}

/// gen_l10n-compat: `BuildContext.l10n` accessor, also re-exported through
/// `app_localizations.dart` for files that import the shim directly.
extension BuildContextL10n on BuildContext {
  /// Slang-backed translations.
  ///
  /// Resolution order:
  /// 1. Flutter `Localizations` (tests and pre-bootstrap error pages using
  ///    [AppLocalizationsCompatDelegate]).
  /// 2. slang's `TranslationProvider` (production; rebuilds on locale change).
  AppLocalizations get l10n {
    final viaLocalizations = Localizations.of<AppLocalizations>(
      this,
      AppLocalizations,
    );
    if (viaLocalizations != null) return viaLocalizations;
    return AppLocalizations.of(this);
  }
}

/// gen_l10n-compat: language tag of this instance's locale (used e.g. for
/// `DateFormat` locale selection).
extension AppLocalizationsLocaleName on AppLocalizations {
  String get localeName => $meta.locale.languageCode;
}
