# Session Tab Member Shells Design

## Goal

Change the chat workspace so each top-level tab represents a FlashskyAI session, not an individual shell. Members remain visible in the right panel, and selecting or opening a member starts or activates that member's shell inside the active session. Terminal sessions are managed in the background instead of being the primary tab model.

## Current Behavior

`ChatCubit` stores `_InternalTab` objects where each tab owns one `TerminalSession`. `openMemberTab` creates a tab with id `member-<memberId>`, so opening two members creates two workspace tabs. `ChatWorkbench` renders the current tab's terminal directly.

## Target Behavior

Workspace tabs are session tabs. Opening a known `FlashskySession` creates or activates a tab for that session. Opening a member does not create a tab. Instead, it updates the active session's selected member and starts or reuses the background `TerminalSession` for that session/member pair.

If no session tab exists, opening a member creates a local session tab for the selected team, then starts that member in the new session. This keeps the UI useful before the user selects a persisted session.

## State Model

`ChatCubit` owns:

- session tab metadata for the visible tabs
- active tab index
- selected member id for the active session
- background member shells keyed by session id and member id
- member running status derived from those background shells

The visible `ChatState.tabs` list contains only session tabs. Member shell state stays internal except for selected member and running status queries used by the right panel.

## UI Flow

The right members panel keeps its current list. Tapping a member calls the new member-shell activation behavior. The selected member highlight changes, and the member running dot turns green after its shell starts. No additional top tab appears.

The center workspace can still display the selected member's terminal for now, but the terminal is no longer what defines the tab. Later work can replace this center with a richer chat timeline without changing the tab/session/member ownership model again.

## Compatibility

`openSessionTab` continues to support resuming historical sessions with `flashskyai --resume <sessionId>`. Existing terminal launch behavior remains unchanged at the `TerminalSession` level. The change is limited to ownership and routing: tabs own sessions, sessions own member shells.

## Testing

Add cubit tests covering:

- opening multiple members creates one session tab, not multiple member tabs
- switching members updates selected member inside the active session
- member running status is tracked per active session/member shell
- opening an existing persisted session keeps the session tab identity

Update widget smoke coverage so the chat workspace still renders with session tabs and member selection.
