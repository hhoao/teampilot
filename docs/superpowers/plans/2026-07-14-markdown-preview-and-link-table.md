# Markdown preview + link/table polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align markdown link/table styles with assistant-ui, and add IDE Source|Preview for `.md` with a Layout preference for default open mode.

**Architecture:** Style polish in `ai_message_ui` + app `buildAppMarkdownStyleSheet`. Session mode map owned by a small `MarkdownViewModeStore` (in-memory). `FileEditorSurface` toolbar toggle + preview body; seed on `WorkbenchEditorOpener.openFile` (not the workbench tab `preview:` pin flag). Preference on `LayoutPreferences`.

**Tech Stack:** Flutter, `flutter_markdown_plus`, `LayoutCubit`, `re_editor`, `url_launcher`.

**Spec:** `docs/superpowers/specs/2026-07-14-markdown-preview-and-link-table-design.md`

---

### File map

| File | Role |
|------|------|
| `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart` | Link/table sheet + optional `onTapLink` |
| `client/lib/theme/app_markdown_style_sheet.dart` | App sheet parity |
| `client/lib/models/layout_preferences.dart` | `MarkdownOpenMode` + JSON |
| `client/lib/cubits/layout_cubit.dart` | setter |
| `client/lib/services/editor/markdown_view_mode_store.dart` | Session map + seed rules |
| `client/lib/widgets/workbench/markdown_view_mode_toggle.dart` | Source\|Preview pill |
| `client/lib/pages/workbench/file_editor_surface.dart` | Wire toggle + preview body |
| `client/lib/services/editor/markdown_preview_link_handler.dart` | Resolve/open links |
| `client/lib/services/workbench/workbench_editor_opener.dart` | Seed mode on openFile |
| `client/lib/pages/config/layout_appearance_in_layout_section.dart` | Settings UI |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Strings |

**Note:** Workbench `openFile(..., preview: true)` means temporary **tab** pin — unrelated to markdown Source|Preview.

---

### Task 1: Link/table styles in `ai_message_ui`

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart`
- Modify: `client/packages/ai_message_ui/test/ai_message_parts_test.dart` (or new markdown sheet test)
- Modify: `client/lib/theme/app_markdown_style_sheet.dart`

- [ ] **Step 1:** Test that `defaultAiMarkdownSheet` sets `a` with primary + underline and non-null table border / head decoration.
- [ ] **Step 2:** Implement sheet fields; add optional `onTapLink` to `AiTextPartView`.
- [ ] **Step 3:** Mirror link/table in `buildAppMarkdownStyleSheet`.
- [ ] **Step 4:** `cd client/packages/ai_message_ui && flutter test`

### Task 2: Preference model

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Modify: `client/test/models/layout_preferences_default_test.dart`
- Modify: `app_en.arb` / `app_zh.arb` + appearance section

- [ ] **Step 1:** Failing round-trip test for `markdownOpenMode`.
- [ ] **Step 2:** Add enum + field + copyWith/toJson/fromJson + `setMarkdownOpenMode`.
- [ ] **Step 3:** Settings dropdown in appearance section + l10n.

### Task 3: Session store + seed on open

**Files:**
- Create: `client/lib/services/editor/markdown_view_mode_store.dart`
- Create: `client/test/services/editor/markdown_view_mode_store_test.dart`
- Modify: `workbench_editor_opener.dart` to call seed when path is markdown

- [ ] **Step 1:** Unit tests for preview/source/remember seed rules.
- [ ] **Step 2:** Implement store + wire opener (inject or singleton/listenable owned by opener/app shell).

### Task 4: Toggle + preview UI

**Files:**
- Create: `markdown_view_mode_toggle.dart`
- Create: `markdown_preview_link_handler.dart`
- Modify: `file_editor_surface.dart`
- Test: widget smoke if feasible

- [ ] **Step 1:** Toggle widget (clone FileDiffSurfaceToggle pattern).
- [ ] **Step 2:** Preview body with MarkdownBody + live controller text + link handler.
- [ ] **Step 3:** Toolbar shows toggle only for md/markdown; body switches on store.

### Task 5: Verify

- [ ] `cd client/packages/ai_message_ui && flutter test`
- [ ] `cd client && flutter test test/models/layout_preferences_default_test.dart test/services/editor/markdown_view_mode_store_test.dart`
- [ ] `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` on touched paths
