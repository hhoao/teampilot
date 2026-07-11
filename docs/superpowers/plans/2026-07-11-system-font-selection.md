# System Font Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users pick UI and monospace fonts via stable preference IDs (`system` + bundled presets), resolved through one `FontCatalog` + `AppFontResolver` path into theme/terminal/editor.

**Architecture:** Preferences store `uiFontId` / `monoFontId` (default `system`). `FontCatalog` declares presets; `AppFontResolver.resolve` produces `ResolvedFonts`; theme builders, warmup, and `loadFontsFor` consume only that result. No full system-font enumeration; no preference migration.

**Tech Stack:** Flutter, `flutter_bloc` (`LayoutCubit`), existing GoogleFonts local pipeline + terminal font assets, `ThemeExtension` (`AppFontTheme`).

**Spec:** `docs/superpowers/specs/2026-07-11-system-font-selection-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| Create `client/lib/theme/font_catalog.dart` | `FontRole`, `FontSourceKind`, `FontCatalogEntry`, `FontCatalog` |
| Create `client/lib/theme/app_font_resolver.dart` | Platform tables, `ResolvedFonts`, `AppFontResolver.resolve` |
| Create `client/lib/theme/app_font_loader.dart` | `loadFontsFor(ResolvedFonts)` (bundled mono assets + UI GoogleFonts when needed) |
| Modify `client/lib/theme/app_fonts.dart` | Keep family name constants; move mono fallback ownership to resolver; `buildAppUiTextTheme` takes `ResolvedFonts` |
| Modify `client/lib/models/layout_preferences.dart` | `uiFontId` / `monoFontId` + normalize helpers |
| Modify `client/lib/cubits/layout_cubit.dart` | `setUiFontId` / `setMonoFontId` |
| Modify `client/lib/theme/app_theme.dart` | Pass `ResolvedFonts` into theme build |
| Modify `client/lib/theme/app_text_styles_warmup.dart` | Warmup uses resolved fonts |
| Modify `client/lib/services/app/ui_interactive_warmup.dart` | Only preload Noto weights when UI id needs bundled load |
| Modify `client/lib/services/terminal/terminal_fonts.dart` | Stop unconditional load; use `AppFontTheme` / loader |
| Modify `client/lib/main.dart` | Boot resolve → load → theme; wire font ids into `_TeamPilotMaterialApp` |
| Create `client/lib/widgets/settings/font_preference_setting.dart` | Dropdown for one role |
| Modify `client/lib/pages/config/layout_appearance_in_layout_section.dart` | Two font rows |
| Modify `client/lib/l10n/app_en.arb`, `app_zh.arb` | Strings (+ run codegen if project requires) |
| Tests under `client/test/theme/`, `client/test/models/` | Catalog, resolver, prefs, theme wiring |

**Out of scope:** Onboarding appearance font UI; enumerating installed fonts.

**Android `system` mono (concrete for implementers):** primary `Noto Sans Mono CJK SC` if treated as available name, else Latin `Droid Sans Mono` / `monospace` only as **last** fallback after SC faces (`Noto Sans Mono CJK SC`, `Noto Sans CJK SC`).

**Silent Ubuntu load:** When mono resolves to `system`, still allow `loadFontsFor` to load Ubuntu Sans Mono **only as a fallback asset** if it appears in the resolved fallback list; do not change stored id. When mono is `jetbrainsMono` / `ubuntuSansMono`, load that primary (and Ubuntu if needed for fallback).

---

### Task 1: FontCatalog

**Files:**
- Create: `client/lib/theme/font_catalog.dart`
- Test: `client/test/theme/font_catalog_test.dart`

- [ ] **Step 1: Write failing catalog tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/font_catalog.dart';

void main() {
  test('uiOptions includes system and notoSansSc', () {
    final ids = FontCatalog.uiOptions.map((e) => e.id).toList();
    expect(ids, containsAll(['system', 'notoSansSc']));
  });

  test('monoOptions includes system, jetbrainsMono, ubuntuSansMono', () {
    final ids = FontCatalog.monoOptions.map((e) => e.id).toList();
    expect(ids, containsAll(['system', 'jetbrainsMono', 'ubuntuSansMono']));
  });

  test('entry unknown id returns system for that role', () {
    expect(FontCatalog.entry(FontRole.ui, 'nope').id, 'system');
    expect(FontCatalog.entry(FontRole.mono, 'nope').id, 'system');
  });

  test('bundled entries expose family names', () {
    expect(
      FontCatalog.entry(FontRole.ui, 'notoSansSc').bundledFamily,
      isNotEmpty,
    );
    expect(
      FontCatalog.entry(FontRole.mono, 'jetbrainsMono').bundledFamily,
      'JetBrainsMono NFM',
    );
  });
}
```

- [ ] **Step 2: Run test — expect FAIL (library missing)**

Run: `cd client && flutter test test/theme/font_catalog_test.dart`

- [ ] **Step 3: Implement `font_catalog.dart`**

```dart
enum FontRole { ui, mono }

enum FontSourceKind { system, bundled }

class FontCatalogEntry {
  const FontCatalogEntry({
    required this.id,
    required this.role,
    required this.source,
    this.bundledFamily,
    this.assetPaths = const [],
  });

  final String id;
  final FontRole role;
  final FontSourceKind source;
  final String? bundledFamily;
  final List<String> assetPaths;
}

abstract final class FontCatalog {
  static const systemId = 'system';

  static const List<FontCatalogEntry> all = [
    FontCatalogEntry(id: systemId, role: FontRole.ui, source: FontSourceKind.system),
    FontCatalogEntry(
      id: 'notoSansSc',
      role: FontRole.ui,
      source: FontSourceKind.bundled,
      bundledFamily: 'Noto Sans SC',
    ),
    FontCatalogEntry(id: systemId, role: FontRole.mono, source: FontSourceKind.system),
    FontCatalogEntry(
      id: 'jetbrainsMono',
      role: FontRole.mono,
      source: FontSourceKind.bundled,
      bundledFamily: 'JetBrainsMono NFM',
      assetPaths: [
        'assets/fonts/terminal/JetBrainsMonoNerdFontMono-Regular.ttf',
      ],
    ),
    FontCatalogEntry(
      id: 'ubuntuSansMono',
      role: FontRole.mono,
      source: FontSourceKind.bundled,
      bundledFamily: 'Ubuntu Sans Mono',
      assetPaths: [
        'assets/fonts/terminal/UbuntuSansMono-Regular.ttf',
        'assets/fonts/terminal/UbuntuSansMono-Bold.ttf',
      ],
    ),
  ];

  static Iterable<FontCatalogEntry> get uiOptions =>
      all.where((e) => e.role == FontRole.ui);

  static Iterable<FontCatalogEntry> get monoOptions =>
      all.where((e) => e.role == FontRole.mono);

  static FontCatalogEntry entry(FontRole role, String id) {
    for (final e in all) {
      if (e.role == role && e.id == id) return e;
    }
    return all.firstWhere(
      (e) => e.role == role && e.id == systemId,
    );
  }

  static bool isKnown(FontRole role, String id) =>
      all.any((e) => e.role == role && e.id == id);
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/theme/font_catalog.dart client/test/theme/font_catalog_test.dart
git commit -m "feat(theme): add FontCatalog for UI and mono presets"
```

---

### Task 2: AppFontResolver + ResolvedFonts

**Files:**
- Create: `client/lib/theme/app_font_resolver.dart`
- Test: `client/test/theme/app_font_resolver_test.dart`
- Modify: `client/lib/theme/app_fonts.dart` (re-export or thin wrappers so existing `AppFonts.monoFamily` / fallback getters still compile; prefer resolver as source of truth for fallbacks)

- [ ] **Step 1: Write failing resolver tests**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/theme/app_font_resolver.dart';

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

  test('linux system mono puts SC before monospace', () {
    final r = AppFontResolver.resolve(
      uiFontId: 'system',
      monoFontId: 'system',
      platform: TargetPlatform.linux,
    );
    expect(r.monoFamily, isNot('monospace'));
    expect(r.monoFamilyFallback.contains('monospace'), isTrue);
    final scIndex = r.monoFamilyFallback.indexOf('Noto Sans Mono CJK SC');
    // primary itself should be SC-capable, or SC appears before monospace in chain
    final chain = [r.monoFamily, ...r.monoFamilyFallback];
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
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/theme/app_font_resolver_test.dart`

- [ ] **Step 3: Implement resolver**

Implement `ResolvedFonts` + `AppFontResolver.resolve` per spec tables:

- macOS UI: `PingFang SC` (readable CJK) with sensible fallbacks  
- Windows UI: `Segoe UI` + `Microsoft YaHei`  
- Linux UI: `Noto Sans` + `Noto Sans CJK SC`, …  
- Android UI: `sans-serif` + CJK fallbacks  
- Mono per spec (Linux/Android: SC before `monospace`)  
- Bundled: use `FontCatalog.entry(...).bundledFamily` + shared mono CJK fallback list (move logic from current `AppFonts.monoFamilyFallback`)

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/theme/app_font_resolver.dart client/lib/theme/app_fonts.dart client/test/theme/app_font_resolver_test.dart
git commit -m "feat(theme): resolve UI/mono fonts via AppFontResolver"
```

---

### Task 3: Preference fields + normalize + cubit setters

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Test: `client/test/models/layout_preferences_default_test.dart` (extend)
- Optional: existing layout cubit test if present; else prefs round-trip is enough

- [ ] **Step 1: Write failing prefs tests**

```dart
test('uiFontId and monoFontId default to system', () {
  expect(const LayoutPreferences().uiFontId, 'system');
  expect(const LayoutPreferences().monoFontId, 'system');
});

test('fromJson missing font keys → system; unknown → system', () {
  expect(LayoutPreferences.fromJson(const {}).uiFontId, 'system');
  expect(
    LayoutPreferences.fromJson(const {'uiFontId': 'nope'}).uiFontId,
    'system',
  );
});

test('font ids round-trip when known', () {
  final prefs = const LayoutPreferences().copyWith(
    uiFontId: 'notoSansSc',
    monoFontId: 'jetbrainsMono',
  );
  final json = prefs.toJson();
  final parsed = LayoutPreferences.fromJson(json);
  expect(parsed.uiFontId, 'notoSansSc');
  expect(parsed.monoFontId, 'jetbrainsMono');
});
```

Add normalize helpers in `font_catalog.dart` or `layout_preferences.dart`:

```dart
String normalizeUiFontId(String? id) =>
    FontCatalog.isKnown(FontRole.ui, id ?? '') ? id! : FontCatalog.systemId;

String normalizeMonoFontId(String? id) =>
    FontCatalog.isKnown(FontRole.mono, id ?? '') ? id! : FontCatalog.systemId;
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Wire fields through constructor, `fromJson`, `copyWith`, `withAtLeastOneToolVisible`, `toJson`; add cubit setters mirroring `setTypographyScale`**

```dart
Future<void> setUiFontId(String id) =>
    _save(state.preferences.copyWith(uiFontId: normalizeUiFontId(id)));

Future<void> setMonoFontId(String id) =>
    _save(state.preferences.copyWith(monoFontId: normalizeMonoFontId(id)));
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/layout_preferences.dart client/lib/cubits/layout_cubit.dart client/test/models/layout_preferences_default_test.dart
git commit -m "feat(layout): persist uiFontId and monoFontId preferences"
```

---

### Task 4: Theme builders consume ResolvedFonts

**Files:**
- Modify: `client/lib/theme/app_fonts.dart` (`buildAppUiTextTheme`, `buildAppFontTheme`)
- Modify: `client/lib/theme/app_theme.dart`
- Test: `client/test/theme/app_font_theme_resolve_test.dart`

- [ ] **Step 1: Write failing theme test**

```dart
test('buildLightTheme applies ResolvedFonts to AppFontTheme', () {
  final fonts = AppFontResolver.resolve(
    uiFontId: 'system',
    monoFontId: 'jetbrainsMono',
    platform: TargetPlatform.linux,
  );
  final theme = buildLightTheme(null, AppTypographyScale.standard, null, fonts);
  final ext = theme.extension<AppFontTheme>()!;
  expect(ext.monoFontFamily, fonts.monoFamily);
  expect(ext.uiFontFamily, fonts.uiFamily);
});
```

- [ ] **Step 2: Run — expect FAIL (signature / wiring)**

- [ ] **Step 3: Change `buildLightTheme` / `buildDarkTheme` / `_applyTypography` to take optional `ResolvedFonts? fonts` defaulting to `AppFontResolver.resolve(uiFontId: 'system', monoFontId: 'system')` so existing call sites (`main` until Task 5, warmup, theme tests, `fatal_app_theme`, `terminal_theme_for_launch`) keep compiling. Wire real prefs in Task 5.**

For UI text theme:
- If `fonts.resolvedUiId == 'notoSansSc'` (or `uiNeedsBundledLoad`): keep GoogleFonts.notoSansScTextTheme path, then `apply` with resolved family/fallback.
- Else: `base.apply(fontFamily: fonts.uiFamily, fontFamilyFallback: fonts.uiFallback)` without forcing Noto.

`buildAppFontTheme` should take `ResolvedFonts` instead of a single `TextStyle uiFont`.

Update test-only path that currently sets `AppFontTheme.fallback` to use the passed `ResolvedFonts`.

- [ ] **Step 4: Fix compile errors at all call sites (`fatal_app_theme.dart`, `terminal_theme_for_launch.dart`, tests). Run theme test — PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/theme/app_fonts.dart client/lib/theme/app_theme.dart client/test/theme/app_font_theme_resolve_test.dart client/lib/pages/system/fatal_app_theme.dart client/lib/services/terminal/terminal_theme_for_launch.dart
git commit -m "feat(theme): build ThemeData from ResolvedFonts"
```

---

### Task 5: Font loader + boot / MaterialApp wiring

**Files:**
- Create: `client/lib/theme/app_font_loader.dart`
- Modify: `client/lib/services/terminal/terminal_fonts.dart`
- Modify: `client/lib/main.dart`
- Modify: `client/lib/theme/app_text_styles_warmup.dart`
- Modify: `client/lib/services/app/ui_interactive_warmup.dart`

- [ ] **Step 1: Implement `loadFontsFor(ResolvedFonts)`**

- Load JetBrains / Ubuntu assets when primary id needs them, or when fallback list includes `Ubuntu Sans Mono` (silent warm for system mono).
- If `uiNeedsBundledLoad`, call existing `GoogleFonts.pendingFonts([GoogleFonts.notoSansSc()])` (and keep weight warmup gated the same way).
- Deprecate/replace unconditional `loadBundledTerminalFonts()` used at boot with `loadFontsFor`.

- [ ] **Step 2: Boot path in `main.dart`**

After layout prefs are available (or with defaults before prefs if boot order requires):

```dart
final fonts = AppFontResolver.resolve(
  uiFontId: prefs.uiFontId,
  monoFontId: prefs.monoFontId,
);
await loadFontsFor(fonts);
```

Adjust `_preloadBundledUiFonts` / `_warmTextLayoutSubsystem` to use resolved UI style (system → `TextStyle(fontFamily: fonts.uiFamily, fontFamilyFallback: fonts.uiFallback)`; bundled Noto → GoogleFonts path).

- [ ] **Step 3: Wire `_TeamPilotMaterialApp`**

Extend `BlocSelector` theme bundle with `uiFontId` / `monoFontId`. Cache keys include both. `_resolveThemes` builds:

```dart
final fonts = AppFontResolver.resolve(
  uiFontId: widget.uiFontId,
  monoFontId: widget.monoFontId,
);
_lightTheme = buildLightTheme(widget.colorPreset, textScale, iconScale, fonts);
_darkTheme = buildDarkTheme(widget.colorPreset, textScale, iconScale, fonts);
```

On font id change, call `loadFontsFor` before/while rebuilding themes (async: if load is async, trigger load then `setState` after — match existing patterns; simplest: `unawaited(loadFontsFor(...))` then rebuild, accepting first frame may fallback).

- [ ] **Step 4: Warmup files use `ResolvedFonts` from current prefs (or system default at early boot)**

- [ ] **Step 5: Manual sanity — app starts; terminal still renders. Commit**

```bash
git add client/lib/theme/app_font_loader.dart client/lib/services/terminal/terminal_fonts.dart client/lib/main.dart client/lib/theme/app_text_styles_warmup.dart client/lib/services/app/ui_interactive_warmup.dart
git commit -m "feat(theme): load and apply resolved fonts at boot and theme rebuild"
```

---

### Task 6: Settings UI + l10n

**Files:**
- Create: `client/lib/widgets/settings/font_preference_setting.dart`
- Modify: `client/lib/pages/config/layout_appearance_in_layout_section.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Regenerate l10n if the project does not check in generated files only — TeamPilot checks in `app_localizations*.dart`; update ARB then run Flutter gen-l10n / existing project command so generated files match.

- [ ] **Step 1: Add ARB keys**

English examples:
- `fontUiTitle`: `Interface font`
- `fontUiDescription`: `UI text. System follows the OS default.`
- `fontMonoTitle`: `Monospace font`
- `fontMonoDescription`: `Terminal, editor, and diffs.`
- `fontOptionSystem`: `System`
- `fontOptionNotoSansSc`: `Noto Sans SC`
- `fontOptionJetbrainsMono`: `JetBrains Mono`
- `fontOptionUbuntuSansMono`: `Ubuntu Sans Mono`

Chinese equivalents in `app_zh.arb`.

- [ ] **Step 2: Build `FontPreferenceSetting` using `SettingsCompactDropdown<String>`** (same pattern as language row). Options from `FontCatalog.uiOptions` / `monoOptions`; labels via l10n switch on id.

- [ ] **Step 3: Insert two `SettingsLabeledRow`s after typography scale in `LayoutAppearanceInLayoutSection`; extend selector tuple with font ids; wire cubit setters.**

- [ ] **Step 4: `cd client && flutter gen-l10n` (or project-equivalent) and `flutter analyze --no-fatal-infos --no-fatal-warnings` on touched files**

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/settings/font_preference_setting.dart client/lib/pages/config/layout_appearance_in_layout_section.dart client/lib/l10n/
git commit -m "feat(settings): add UI and monospace font preference controls"
```

---

### Task 7: Verification

- [ ] **Step 1: Run focused tests**

```bash
cd client && flutter test test/theme/font_catalog_test.dart test/theme/app_font_resolver_test.dart test/theme/app_font_theme_resolve_test.dart test/models/layout_preferences_default_test.dart
```

Expected: all PASS

- [ ] **Step 2: Run broader check**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

Expected: analyze clean enough for CI norms; tests pass (fix any breakage from theme signature changes).

- [ ] **Step 3: Mark spec status Implemented (or leave Draft until merge) — optional doc tweak**

- [ ] **Step 4: Final commit only if verification fixed stragglers**

---

## Execution notes

- Follow TDD per task; do not skip failing-test steps.
- Prefer `@superpowers:subagent-driven-development` with one fresh subagent per task.
- Do not add onboarding font UI.
- Do not enumerate system fonts.
