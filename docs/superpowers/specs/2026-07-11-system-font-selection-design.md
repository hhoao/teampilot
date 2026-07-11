# System Font Selection (UI + Mono)

**Date:** 2026-07-11  
**Status:** Implemented  
**Owner decision:** Declarative `FontCatalog` + single `AppFontResolver`; preferences store stable IDs only; default both UI and mono to `system` on all platforms; no backward/forward compatibility for prior hard-coded Noto / JetBrains defaults.

## Problem

TeamPilot hard-codes UI typography to bundled **Noto Sans SC** (`GoogleFonts.notoSansSc`) and code/terminal faces to **JetBrains Mono NFM**, with platform CJK fallbacks only for mono. Appearance settings expose text size and UI zoom, but not font family. Users who want OS-native UI type or a different mono face cannot choose without code changes. Font resolution is also scattered (`app_fonts.dart`, theme builders, `terminal_fonts.dart`, editor theme), so adding choices would duplicate platform/`if` logic.

## Goals

- Separate **UI** and **monospace** font preferences.
- Presets + **Follow system** only — do **not** enumerate all installed system fonts.
- Default both preferences to **`system`** (new installs and existing installs; no migration of old implicit Noto/JetBrains).
- Support **all platforms** (Linux, macOS, Windows, Android).
- One resolution path consumed by UI `TextTheme`, `AppFontTheme`, terminal, file editor, diff, and glyph warmup.
- Keep CJK readability: Linux mono `system` must prefer SC CJK faces over JP-biased `monospace` (preserve today’s punctuation rationale).

## Non-goals

- Full system font picker / fontconfig dump / “browse all fonts”.
- Per-workspace or per-session font overrides.
- Changing typography scale / UI zoom behavior.
- Shipping new font binary assets beyond fonts already bundled (Noto via `google_fonts/`, JetBrains + Ubuntu Sans Mono under `assets/fonts/terminal/`).
- Preserving prior default appearance for users who never set a font ID.
- Remote/SSH host fonts (client UI/terminal rendering stays on the local Flutter process).

## Decision

**FontCatalog (data) + AppFontResolver (logic) + preference IDs.**

```text
FontCatalog
  → LayoutPreferences.uiFontId / monoFontId  (default: system)
  → AppFontResolver.resolve(...)
  → ResolvedFonts
  → Theme / AppFontTheme / terminal / editor / warmup
```

Do not store raw `fontFamily` strings in preferences. Do not resolve fonts inside individual widgets.

## Architecture

### Preference model

Add to `LayoutPreferences` (and JSON persistence via existing layout prefs path):

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `uiFontId` | `String` | `'system'` | UI sans preference |
| `monoFontId` | `String` | `'system'` | Terminal / editor / diff mono preference |

- `normalizeUiFontId` / `normalizeMonoFontId`: empty or unknown → `'system'`. Validity is defined by `FontCatalog` for that role.
- `LayoutCubit.setUiFontId` / `setMonoFontId`: same pattern as `setTypographyScale` (update prefs → persist → theme host rebuilds from new `ResolvedFonts`).
- No distinction between “unset” and explicit `system`. Missing JSON keys deserialize as `system`.

### FontCatalog

Roles and sources:

```dart
enum FontRole { ui, mono }

enum FontSourceKind {
  system,   // platform strategy in AppFontResolver
  bundled,  // app assets / GoogleFonts local pipeline
}
```

Catalog entry fields (declarative):

| Field | Role |
|-------|------|
| `id` | Stable id (`system`, `notoSansSc`, `jetbrainsMono`, …) |
| `role` | `ui` or `mono` |
| `source` | `system` or `bundled` |
| `l10nKey` | Settings label |
| `bundledFamily` | Family name when `bundled` |
| `assetHints` | Mono asset paths and/or UI GoogleFonts identity for loaders |

`system` entries carry **no** family names — families live only in the resolver’s platform tables.

**v1 catalog**

| id | role | source |
|----|------|--------|
| `system` | ui | system |
| `notoSansSc` | ui | bundled |
| `system` | mono | system |
| `jetbrainsMono` | mono | bundled |
| `ubuntuSansMono` | mono | bundled (existing terminal assets) |

API: `uiOptions` / `monoOptions`; `entry(role, id)` returns that role’s `system` entry when id is unknown.

### AppFontResolver

```dart
ResolvedFonts AppFontResolver.resolve({
  required String uiFontId,
  required String monoFontId,
  TargetPlatform platform = defaultTargetPlatform,
})
```

**`ResolvedFonts`** (only type consumers should need):

| Field | Use |
|-------|-----|
| `uiFamily` / `uiFallback` | `TextTheme`, `AppFontTheme` |
| `monoFamily` / `monoFallback` | Terminal, editor, diff, `appMonoTextStyle` |
| `uiNeedsBundledLoad` / `monoNeedsBundledLoad` | Startup / preference-change loading |
| `resolvedUiId` / `resolvedMonoId` | Effective catalog ids after normalize |

Rules:

1. Look up catalog entry; illegal id → that role’s `system`.
2. `bundled` → entry `bundledFamily` + shared role fallback chain.
3. `system` → platform strategy tables below.
4. No `TargetPlatform` switches in theme widgets or terminal style helpers.

**`system` UI**

| Platform | Primary | Fallback (representative) |
|----------|---------|---------------------------|
| macOS | `.AppleSystemUIFont` or `PingFang SC` | system UI / CJK-capable faces |
| Windows | `Segoe UI` | `Microsoft YaHei`, emoji face as needed |
| Linux | `Noto Sans` or generic sans | `Noto Sans CJK SC`, `WenQuanYi Zen Hei`, … |
| Android | `sans-serif` | CJK-capable system faces when available |

**`system` mono**

On Linux/Android, **do not** use bare `monospace` as the primary family. fontconfig often maps `monospace` (even with `lang=zh`) to *Noto Sans Mono CJK JP*, which covers CJK so SC fallbacks never run and Chinese punctuation is wrong. Put an SC-capable face **before** the generic `monospace` alias (same rationale as today’s `AppFonts.monoFamilyFallback`).

| Platform | Primary | Fallback (order matters) |
|----------|---------|--------------------------|
| macOS | `Menlo` | `Ubuntu Sans Mono` (if loaded), `PingFang SC`, `Heiti SC`, `monospace` |
| Windows | `Consolas` | `Ubuntu Sans Mono` (if loaded), `Microsoft YaHei`, `monospace` |
| Linux | `Noto Sans Mono CJK SC` (or `Ubuntu Sans Mono` when that bundled face is loaded as a silent fallback) | `Noto Sans CJK SC`, `WenQuanYi Zen Hei Mono`, then `monospace` last |
| Android | Prefer an SC-capable mono/sans if the platform exposes one; otherwise a Latin mono | SC CJK faces, then `monospace` **last** |

Bundled mono fallbacks reuse today’s CJK mono list (move from `AppFonts.monoFamilyFallback` into shared constants owned by catalog/resolver). UI `notoSansSc` uses the existing GoogleFonts / local `google_fonts/` pipeline.

**Loading**

- `loadFontsFor(ResolvedFonts)` loads only required bundled assets / UI font files.
- `system` loads nothing.
- Boot and preference changes: `resolve(prefs)` → `loadFontsFor` → `buildLightTheme` / `buildDarkTheme` with `ResolvedFonts`.
- Asset load failure: log; keep preferred family name (Flutter falls through fallbacks). Do **not** silently rewrite the stored preference id.

### Theme, terminal, editor integration

- `buildLightTheme` / `buildDarkTheme` take `ResolvedFonts` and apply families to `TextTheme` + `AppFontTheme`.
- Remove hard-coded `GoogleFonts.notoSansSc()` from `buildAppUiTextTheme` as the sole path; build from `ResolvedFonts`.
- Terminal / editor / diff keep reading `context.appFonts` (populated from `ResolvedFonts`).
- `kTerminalFontFamily` (or equivalent) remains a **bundled catalog family name**, not “the active terminal font”.
- Replace unconditional `loadBundledTerminalFonts()` with `loadFontsFor(ResolvedFonts)` (load JetBrains / Ubuntu only when needed for primary or fallback).
- Glyph warmup (`app_text_styles_warmup`) must use the same resolved fonts as the running theme so boot warmup matches runtime.

### Settings UI

In `LayoutAppearanceInLayoutSection` (near typography scale):

- Rows: UI font / mono font.
- Options from `FontCatalog.uiOptions` / `monoOptions` (includes Follow system).
- Optional preview using the resolved family for the selected id.
- Wire to `LayoutCubit.setUiFontId` / `setMonoFontId`.

**l10n (en + zh ARB):** titles/descriptions plus option labels for `system`, `notoSansSc`, `jetbrainsMono`, `ubuntuSansMono`.

## Error handling

| Case | Behavior |
|------|----------|
| Unknown preference id | Normalize to `system` |
| Bundled asset missing | Log warning; keep family; rely on fallbacks |
| Platform missing preferred system face | Flutter / OS fallback along `uiFallback` / `monoFallback` |

## Testing

- Normalize helpers and catalog unknown-id → `system`.
- Resolver snapshots per platform for `system` UI/mono primary + critical fallback ordering (especially Linux/Android: SC-capable face before bare `monospace`).
- Bundled ids resolve to expected family names.
- Theme build: `AppFontTheme` / text theme families match injected `ResolvedFonts`.
- Cubit: setters persist `uiFontId` / `monoFontId`.
- Prefer constructor-injected platform in resolver tests (no real font enumeration).

## File touch map (indicative)

| Area | Path |
|------|------|
| Catalog + resolver | `client/lib/theme/font_catalog.dart`, `app_font_resolver.dart` (names flexible) |
| Prefs / cubit | `layout_preferences.dart`, `layout_cubit.dart` |
| Theme | `app_fonts.dart`, `app_theme.dart`, `app_text_styles_warmup.dart`, any other `GoogleFonts.notoSansSc` warmup helpers, `main.dart` |
| Terminal | `terminal_fonts.dart` |
| Settings | `layout_appearance_in_layout_section.dart` + small setting widget |
| l10n | `app_en.arb`, `app_zh.arb` |
| Tests | `test/theme/`, `test/models/`, cubit coverage as needed |

## Out of scope (UI surfaces)

- **Onboarding appearance** stays unchanged in v1 — font pickers live only under layout/appearance settings (`LayoutAppearanceInLayoutSection`). Do not add a second font UI on the onboarding step unless a follow-up explicitly asks for it.

## Open implementation notes

- Exact macOS UI primary (`.AppleSystemUIFont` vs `PingFang SC`) can be tuned in resolver constants during implementation as long as CJK remains readable.
- Whether Ubuntu Sans Mono stays a **user-visible mono preset** and/or a silent fallback asset is catalog data; v1 exposes it as a preset because assets already ship.
- Audit other hard-coded `GoogleFonts.notoSansSc` call sites (e.g. interactive warmup helpers) so boot/warmup stay on the single `ResolvedFonts` path.
