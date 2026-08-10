# Session Tab Title During Launch — Design

**Date:** 2026-08-10
**Status:** Approved (design review)

## Problem

When a new session is started, the session tab in the workspace tab strip is
blank until launch/connect finishes. The sidebar already falls back to
`defaultNewChatSessionTitle` ("New Chat"), but the center-strip session chip
paints `AppSession.display` directly, and `display` is empty for a new session.

For compose-landing launches that carry an initial prompt, the title is set
only after the member is connected and the prompt is delivered
(`submitWorkspaceLandingMessage` → `_ensureLandingSessionConnected` →
inject → `applyFirstPromptTitle`), so the tab stays blank during the slow
connect phase.

## Goals

1. A session tab always shows a non-empty title, even while the session is
   unnamed or still launching.
2. When a session is launched with an initial prompt, its derived title appears
   as soon as the session is opened, not after connect + delivery completes.
3. Keep the existing "first prompt wins, never overwrite a manual title" rule.

## Design

### 1. Tab chip empty-title fallback

In `WorkbenchStripTabChipState.build`
(`client/lib/pages/workspace_shell/workspace_shell_tabs.dart`), when
`sessionId != null` and the live title from
`SessionRowContent.fromChatState(...).titleForPaint` is empty, paint
`context.l10n.defaultNewChatSessionTitle` instead.

This mirrors the existing sidebar behavior in
`client/lib/widgets/sidebar_session_tile.dart:317` and does not affect
file/diff/shell/run tabs.

### 2. Rename from landing prompt before connect

In `submitWorkspaceLandingMessage`
(`client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`),
call `chatCubit.applyFirstPromptTitle(session.sessionId, trimmed)` right after
the session is resolved and before `_ensureLandingSessionConnected`. Remove the
later call after delivery.

The rename is best-effort: wrap it in try/catch and log failures with
`appLogger`; a title-write failure must not block or abort the connect.
`SessionPromptMetadataSync` already skips renaming when `display` is non-empty,
so it cannot overwrite a manual title or race with the keyboard
`FirstUserLineCapture` path.

### 3. Testing

- Widget test: a session `WorkbenchStripTabChip` with an empty `display` paints
  "New Chat" (localized fallback), not an empty string.
- Keep the existing `SessionPromptMetadataSync` unit tests
  (`client/test/services/launch/session_prompt_metadata_sync_test.dart`); they
  already cover first-prompt rename, skip-when-named, and blank-prompt skip.
- Run `flutter analyze --no-fatal-infos --no-fatal-warnings` and
  `flutter test --exclude-tags integration`.

## Non-goals

- Persisting an initial derived title at `createSession` time; the existing
  rename path is sufficient once it runs before connect.
- Changing the sidebar, search, notification, or terminal fallbacks; they
  already use `defaultNewChatSessionTitle`.
