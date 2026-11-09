// Transitional compat entry point.
//
// Re-exports slang's generated translations (flat keys, same `AppLocalizations`
// class name as the old gen_l10n output) plus the hand-written compat layer, so
// existing imports of this file keep compiling unchanged.
//
// Regenerate slang output with `dart run slang` after editing
// app_en.arb / app_zh.arb (see slang.yaml).
export 'l10n_compat.dart';
export 'translations.g.dart' hide BuildContextTranslationsExtension;
export 'translations_zh.g.dart' show AppLocalizationsZh;
