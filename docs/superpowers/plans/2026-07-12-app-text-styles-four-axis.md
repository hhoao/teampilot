# Four-axis AppTextStyles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace semantic `AppTextStyles` names with a four-axis named-getter scale (`md`, `mdSemibold`, `xsBoldWide`, …), private `_compose` only, full call-site migration, no backward compatibility.

**Architecture:** `AppTextStyles` owns private enums + `_compose`; public API is a closed set of named getters (+ `*Colored`, `muted*`, `mono`). Warmup enumerates every shipped getter. UI layers use only these tokens.

**Tech Stack:** Flutter, `client/lib/theme/app_text_styles.dart`, warmup, CODE_QUALITY

**Spec:** `docs/superpowers/specs/2026-07-12-app-text-styles-scale-naming-design.md`  
**Worktree:** `/home/hhoa/git/hhoa/teampilot/.worktrees/app-text-styles-enforcement`

---

### Rename map (apply everywhere)

| Old | New |
|-----|-----|
| `caption` / `captionColored` | `xs` / `xsColored` |
| `badge` / `badgeColored` | `xsSemiboldSnug` / `xsSemiboldSnugColored` |
| `toolPanelTitle` / `toolPanelTitleColored` | `xsBoldWide` / `xsBoldWideColored` |
| `settingsGroupHeader` / `settingsGroupHeaderColored` | `xsTrack` / `xsTrackColored` |
| `fileTreeRootLabel(c)` | `mdBoldSpreadColored(c)` |
| `fileTreeEntryLabel(color:, active: true)` | `mdSemiboldColored(color)` |
| `fileTreeEntryLabel(color:, active: false)` | `mdMediumColored(color)` |
| `bodySmall` / `bodySmallColored` | `sm` / `smColored` |
| `body` / `bodyColored` | `md` / `mdColored` |
| `formLabel` / `formLabelColored` | `mdSnug` / `mdSnugColored` |
| `bodyStrong` / `bodyStrongColored` | `mdSemibold` / `mdSemiboldColored` |
| `prominent` | `lg` |
| `sectionTitle` / `sectionTitleColored` | `mdSemiboldTightSnug` / `mdSemiboldTightSnugColored` |
| `subtitle` | `lgSnug` |
| `pageTitle` | `xl` |
| `pageHeadline` | `display` |
| `dialogTitle` | `lgSemiboldSnug` |
| `mutedBody` | `mutedMd` |
| `mutedBodySmall` | `mutedSm` |
| `mutedCaption` | `mutedXs` |
| `mono` / `monoColored` | unchanged |

Also map any `styles.body.copyWith(fontWeight: FontWeight.w600)` → `mdSemibold`, etc. (promote to named token + warmup).

---

### Task 1: Rewrite AppTextStyles + warmup + CODE_QUALITY

**Files:**
- Rewrite: `client/lib/theme/app_text_styles.dart`
- Modify: `client/lib/theme/app_text_styles_warmup.dart`
- Modify: `docs/CODE_QUALITY.md` (Typography row — use spec wording)

- [ ] **Step 1:** Implement private `_TextSize` / `_TextWeight` / `_TextSpacing` / `_TextHeight` + `_compose` per spec metric tables.
- [ ] **Step 2:** Ship all getters in the spec “Initial shipped combination set” + `*Colored` for each + `mutedXs/Sm/Md` + `mono`/`monoColored`. Delete all old semantic getters.
- [ ] **Step 3:** Warmup lists every shipped getter (and mono).
- [ ] **Step 4:** Update CODE_QUALITY Typography cell to four-axis named tokens rule from spec.
- [ ] **Step 5:** Commit: `refactor(styles): four-axis AppTextStyles API with private compose`

Note: call sites will not compile until Task 2 — that is expected; proceed immediately to Task 2 in the same session.

---

### Task 2: Mechanical rename of all AppTextStyles call sites

**Files:** all under `client/lib/` + `client/test/` that reference old names (expect ~100+ files).

- [ ] **Step 1:** Apply rename map (including method renames like `fileTreeRootLabel` → `mdBoldSpreadColored`).
- [ ] **Step 2:** Fix `fileTreeEntryLabel` call sites to branch on `active` with `mdSemiboldColored` / `mdMediumColored`.
- [ ] **Step 3:** Grep for old names (`caption`, `bodyStrong`, `sectionTitle`, `toolPanelTitle`, `mutedBody`, `badge`, `formLabel`, `pageTitle`, `prominent`, `dialogTitle`, `subtitle`, `bodySmall`, `bodyColored`, `settingsGroupHeader`, `fileTree`) — zero hits outside git history / docs/plans.
- [ ] **Step 4:** Commit: `refactor(styles): rename call sites to four-axis AppTextStyles tokens`

---

### Task 3: Markdown + LlmWorkspaceText facade removal

**Files:**
- `client/lib/theme/app_markdown_style_sheet.dart`
- `client/lib/pages/llm_config/llm_workspace_typography.dart` (+ all importers)
- Any other `*Typography` facade under pages/widgets

- [ ] **Step 1:** Rebind markdown styles to scale tokens (`md`, `lgSnug`, `lgSemiboldSnug`, …).
- [ ] **Step 2:** Delete facade; update call sites to `AppTextStyles.of(context).*`.
- [ ] **Step 3:** Commit: `refactor(styles): drop typography facades; bind markdown to scale tokens`

---

### Task 4: Finish remaining raw textTheme / metric copyWith in pages/

**Files:** any remaining `textTheme.` or metric `copyWith` under `client/lib/pages/` (and leftover widgets).

- [ ] **Step 1:** Migrate to scale tokens; add new shipped getters + warmup if a combo is missing.
- [ ] **Step 2:** Grep gate:

```bash
rg -n 'textTheme\.(body|label|title|headline)|TextStyle\(|\.copyWith\([^)]*font(Size|Weight)|letterSpacing:|height:\s*1\.' \
  client/lib/pages client/lib/widgets --glob '*.dart' \
  | rg -v 'provider_brand_icon|team_hub_visuals|side_by_side_diff|unified_diff|appTerminalTextStyle|TerminalStyle|app_text_styles\.dart'
```

- [ ] **Step 3:** Commit: `refactor(styles): migrate remaining pages textTheme to scale tokens`

---

### Task 5: Verify

- [ ] **Step 1:** From worktree, if Flutter deps resolve: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`. If submodule missing, fix path or analyze from main checkout with worktree files — report either way.
- [ ] **Step 2:** Confirm warmup list == public getters (manual diff).
- [ ] **Step 3:** Commit any leftover fixes: `fix(styles): finish four-axis typography enforcement`
- [ ] **Step 4:** Stop for finishing-a-development-branch (do not merge/push unless user asks)

---

## Notes

- Work only in the worktree path above.
- No public `compose`. No old-name aliases.
- Prefer `final styles = AppTextStyles.of(context);` once per build.
- Do not push.
