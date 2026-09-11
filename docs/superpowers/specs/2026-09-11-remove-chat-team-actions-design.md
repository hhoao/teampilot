# Remove Chat Page Team Actions Bar

## Scope

Remove the chat page's top action row containing the single-member
(`team-lead`) and whole-team launch buttons. Keep the Chat/Terminal icon toggle
visible and functional. Keep the reusable `WorkspaceShellActionsBar` widget and
the underlying `ChatCubit.openMemberTab` / `launchAllMembers` capabilities
unchanged for other callers.

## Approach

Remove the chat-specific `chatActions` construction, its `_chatActions` helper,
and the two places where those actions are passed/rendered in
`ChatPageShell`. The surrounding workbench and split-group layout remain
unchanged; an empty action list means no extra top row is rendered. The
`SessionWorkbenchViewIcons` / `SessionWorkbenchViewToggle` wiring in
`chat_workbench.dart` is not modified.

## Verification

Add or update a focused widget-level assertion for the chat shell so the
removed action keys are absent while the existing session workbench toggle
coverage remains intact. Run the focused test through
`dart run tool/run_tests.dart`, then run `flutter analyze --no-fatal-infos
--no-fatal-warnings` and the required full test command before completion.
