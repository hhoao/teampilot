# Streaming team generation with progress — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Generate teams via a streaming (`stream-json`) headless call so the new-team dialog can show a progress bar that advances per JSON event, then auto-creates the team and closes on completion.

**Architecture:** Extend `HeadlessRunCapability` with streaming (`supportsStreaming` + `streamResultText`); claude/flashskyai emit `--output-format stream-json --verbose`. `HeadlessAiService.runStreaming` reads stdout line-by-line, invoking `onEvent` per NDJSON line. `TeamConfigGenerator.generateStreaming(onProgress)` bumps progress per event (asymptotic, never 100% mid-stream) and parses the final result. The AI tab's primary button becomes **生成**: click → progress bar → auto-create + close; non-streaming CLIs animate the same easing bar on a timer.

**Decisions:** auto-create + close on completion (no review step); time-based asymptotic fallback for non-stream CLIs.

**Tech Stack:** Dart/Flutter, `Process.start` stdout streaming, `flutter_bloc`.

---

## Task 1: Headless streaming capability + service

- Extend `HeadlessRunContext` with `bool stream = false`.
- Add to `HeadlessRunCapability`: `bool get supportsStreaming;` and `String? streamResultText(String line);`.
- claude/flashskyai: `supportsStreaming => true`; `buildInvocation` adds `--output-format stream-json --verbose` when `ctx.stream`; `streamResultText` parses `{"type":"result","result": "..."}`.
- codex/opencode/cursor: `supportsStreaming => false`; `streamResultText(_) => null`.
- `HeadlessAiService`: add `HeadlessStreamRunner` seam + `runStreaming({setting, prompt, onEvent})` that reads stdout lines, calls `onEvent` per non-empty line, captures the last `streamResultText`, returns `HeadlessAiResult`.
- Tests: capability `streamResultText` parsing; service `runStreaming` with a fake stream runner emitting canned NDJSON lines (asserts onEvent count + final text).

## Task 2: Streaming generator

- `TeamConfigGenerator.generateStreaming({setting, description, mode, joinedAt, onProgress})`: builds the prompt, calls `runStreaming` (with a streaming runner seam), increments an event counter, maps it to asymptotic progress `1 - exp(-events/K)` capped ~0.92 via `onProgress`, parses the final text into a draft. No JSON-repair retry (single streamed attempt); throws `TeamDraftFormatException` on parse failure.
- Tests: progress callback fires and is monotonic < 1.0; returns parsed draft.

## Task 3: Dialog AI-tab streaming UX

- Remove the generate button from `HomeWorkspaceTeamGenerateSection`; it becomes a controlled description field reporting `onDescriptionChanged`. The dialog owns the description + progress.
- AI-tab primary button label → **生成**; on press: start streaming generate, show a `LinearProgressIndicator(value: _progress)`; on success `addTeam(draft)` + `Navigator.pop`; on error stop + snackbar (keep open).
- Non-streaming CLIs: animate `_progress` on a periodic timer toward ~0.92.
- Tests: section reports description; (widget) button disabled until mode + description.

## Verification

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` (note the 4 pre-existing flaky failures in plugin/team_hub page tests, unrelated).
