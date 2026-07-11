# Installed System Font Picker (extension)

**Date:** 2026-07-11  
**Status:** Implemented  
**Extends:** [2026-07-11-system-font-selection-design.md](./2026-07-11-system-font-selection-design.md)  
**Owner decision:** Mixed list (presets on top + searchable installed fonts); full lists for UI and mono with mono-like names soft-sorted first; desktop via vendored [hhoao/system_fonts](https://github.com/hhoao/system_fonts) submodule; no `native_font`; Android v1 stays presets + `system` only when enumeration is unavailable.

## Problem

v1 font pickers only expose catalog presets (`system` + bundled). Users want to pick any installed desktop font without leaving the app.

## Goals

- Settings: **System + bundled presets pinned at top**, then **families discovered by vendored `system_fonts`** (after fork fixes), with **search**.
- Mono list: **soft-prioritize** names suggesting monospace (`Mono`, `Consolas`, `Menlo`, …); **do not hard-filter**.
- Persist selection as a stable preference id; resolve through existing `AppFontResolver` / `loadFontsFor` **with an explicit `installed:` short-circuit** (must not fall through catalog → `system`).
- Vendor and improve fonts via submodule `client/packages/system_fonts` (fork of system_fonts).

## Non-goals

- `native_font` package.
- Perfect typographic classification (isMono from OS APIs).
- Loading every system font at startup (`loadAllFonts`).
- Claiming parity with the full OS font menu (no `.ttc` / fontconfig display-name merge in v1 unless added later in the fork).
- Full installed-font enumeration on Android in v1 (graceful degrade to presets + `system`).

## Decision

```text
FontCatalog presets
  + InstalledFontEnumerator (system_fonts on desktop)
  → preference id: system | <catalogId> | installed:<key>
  → AppFontResolver / loadFontsFor  (installed: handled BEFORE catalog unknown→system)
  → searchable mixed dropdown
```

**v1 discovery contract:** the picker’s installed section is exactly what `SystemFonts.getFontList()` returns after the listed fork fixes (recursive `.ttf`/`.otf` under the package’s directory set, basename keys) — not “every face the OS UI shows.”

## Architecture

### Submodule

| Item | Value |
|------|--------|
| Path | `client/packages/system_fonts` |
| Remote | `https://github.com/hhoao/system_fonts.git` |
| pubspec | `system_fonts: path: packages/system_fonts` |

### Fork fixes (in submodule)

1. **Recursive** directory scan (Linux nested font dirs).
2. Dedupe keys; stable sorted `getFontList()`.
3. **`await` `FontLoader.load()`** in `loadFont` (current code fires load without awaiting).
4. Optional later: Linux `fc-list` for display names — **not required for v1** (file basename keys OK).

### Preference encoding

| Value | Meaning |
|-------|---------|
| `system` | Platform default strategy (unchanged) |
| catalog id (`notoSansSc`, …) | Bundled preset |
| `installed:<key>` | Key from `SystemFonts.getFontMap()` / `getFontList()` |

- Helpers: `isInstalledFontId(id)` / `installedFontKey(id)`.
- `normalizeUiFontId` / `normalizeMonoFontId`: if `isInstalledFontId` and key non-empty → keep; else if `FontCatalog.isKnown` → keep; else → `system`. **Must not** treat `installed:*` as unknown catalog id.
- Cross-device: keep `installed:*` on Android; enumerator returns `[]`; load no-op; resolver still sets family to key + role fallbacks (glyphs may use fallbacks).
- Missing file at runtime: keep preference; load may return null; fallbacks still apply.

### Resolver + loader

**Order in `AppFontResolver.resolve` (per role):**

1. If id is `installed:<key>` with non-empty key → family = key, role fallbacks, `resolved*Id` = full id, `*NeedsBundledLoad` = false, `*NeedsInstalledLoad` = true.
2. Else catalog entry as today (`system` / bundled).

- `ResolvedFonts` gains `uiNeedsInstalledLoad` / `monoNeedsInstalledLoad` (or a single clear pair of bools). **`loadFontsFor` uses these flags only** (no duplicate prefix parsing in the loader).
- Do not call `loadAllFonts()` at boot — only selected installed face(s).

### Enumerator service (app)

- `InstalledFontEnumerator.listFamilies()` → `Future<List<String>>`, cached; empty on Android / unsupported / failure.
- Deduplicate against catalog bundled family names where obvious (optional).

### Settings UI

- Replace compact-only preset dropdown with searchable mixed list:
  1. System + catalog options for that role
  2. “Installed” section label (l10n)
  3. Installed families (mono: mono-like names first, then A–Z)
- **Search filters the entire list** (presets + installed).
- l10n: search hint + installed section title.
- Async: show presets immediately; fill installed when scan completes.

## Testing

- Preference normalize accepts `installed:Foo`, rejects empty key.
- Resolver maps `installed:Foo` to family `Foo`.
- Enumerator returns empty when platform unsupported (unit with fake).
- Widget: presets remain visible before/without installed list.

## File touch map

| Area | Path |
|------|------|
| Submodule | `client/packages/system_fonts`, `.gitmodules` |
| Enumerator | `client/lib/theme/installed_font_enumerator.dart` (name flexible) |
| Prefs / resolver / loader | existing font preference pipeline |
| Settings | `font_preference_setting.dart` (+ search UI) |
| Spec parent | update non-goal “no enumeration” as superseded by this doc |
