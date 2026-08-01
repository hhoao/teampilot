# `tp_markdown` package extraction

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Move the semantic markdown stack out of `ai_message_ui` into publish-ready `client/packages/tp_markdown/` without regressing layout, cache, or chat/preview wiring.

**Architecture doc:** `docs/superpowers/specs/2026-08-02-tp-markdown-package-design.md`

**Tech stack:** Flutter path package, `package:markdown`, existing IR/render code (move + rename imports).

---

### Task 1: Move sources into `tp_markdown`

**Files:**
- Create: `client/packages/tp_markdown/pubspec.yaml`, `lib/tp_markdown.dart`, README, CHANGELOG
- Move from `ai_message_ui/lib/src/markdown/`:
  - `ir/*` → `tp_markdown/lib/src/ir/`
  - `tokens/*` → `tp_markdown/lib/src/tokens/`
  - `content_compiler.dart`, `streaming_markdown.dart`, `content_truncate.dart` → `tp_markdown/lib/src/compile/`
  - `render/*` → `tp_markdown/lib/src/render/`
  - `registry/*` → `tp_markdown/lib/src/registry/`
- Keep in `ai_message_ui`: `compiled_markdown_chrome.dart` only (update import to `package:tp_markdown`)

- [ ] **Step 1:** `git mv` the modules into the layout above
- [ ] **Step 2:** Rewrite relative imports to `package:tp_markdown/src/...` or relative within package
- [ ] **Step 3:** Add `MarkdownStrings` + wire code-block chrome (no `AiMessageStrings`)
- [ ] **Step 4:** Export barrel `lib/tp_markdown.dart`
- [ ] **Step 5:** `cd client/packages/tp_markdown && flutter pub get`

### Task 2: Retarget `ai_message_ui` + app

- [ ] **Step 1:** Add path dep `tp_markdown` to `ai_message_ui/pubspec.yaml`; remove direct `markdown` if unused
- [ ] **Step 2:** Update all `ai_message_ui` imports; re-export markdown public API from `ai_message_ui.dart`
- [ ] **Step 3:** `TextPartView` (and any `MarkdownView` call sites) pass `MarkdownStrings` from `AiMessageStrings`
- [ ] **Step 4:** App `pubspec.yaml`: path dep `tp_markdown` if preview imports it directly; update preview imports optionally to `package:tp_markdown`
- [ ] **Step 5:** `flutter pub get` at client

### Task 3: Move tests + verify

- [ ] **Step 1:** Move markdown unit/widget tests to `tp_markdown/test/`
- [ ] **Step 2:** Keep chat-only tests in `ai_message_ui`; update imports
- [ ] **Step 3:** `cd client/packages/tp_markdown && flutter test`
- [ ] **Step 4:** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- [ ] **Step 5:** `cd client && flutter test --exclude-tags integration` (or focused markdown + preview + ai_message_ui tests if full suite too long — prefer full exclude-tags)

### Task 4: Docs + commit

- [ ] **Step 1:** Spec already at `docs/superpowers/specs/2026-08-02-tp-markdown-package-design.md`; note supersede in semantic-renderer spec packaging row if editing lightly
- [ ] **Step 2:** Commit on `feat/tp-markdown-package` when green
