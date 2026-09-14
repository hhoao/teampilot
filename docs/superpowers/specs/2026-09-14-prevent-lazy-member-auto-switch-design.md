# Prevent Lazy Member Auto-Switch Design

## Goal

Team-mode background and lazy member startup must not change the currently selected member or the visible member page. A member is selected only when the user explicitly chooses the member or invokes an explicit open/switch action.

## Current behavior and root cause

`SessionMemberConnectScheduler.schedule` supports a `selectMember` flag, but defaults it to `true`. Some background materialization paths call it without overriding that default. The scheduler then writes the launching member into `ChatTab.selectedMemberId`, which causes the member-specific surface to rebuild and appear to switch pages.

Batch launch already passes `selectMember: false` for non-initial/background members. The missing cases are lazy terminal restoration and TeamBus-driven materialization. Explicit `openMemberTab` remains a user-directed action and should continue selecting the requested member.

## Design

Keep selection and materialization as separate concerns:

- `TabMemberMaterializer.materializeMember` schedules a member shell with `selectMember: false`; it can be invoked by background TeamBus delivery or other non-UI flows.
- `SessionLaunchService.ensureMemberTerminalForView` schedules a member shell with `selectMember: false`; `selectMember` has already recorded the user's selection before this method is called.
- Explicit member-opening paths continue using the scheduler's selecting behavior, so clicking “Open member” or an equivalent explicit action still changes the visible member.

No route model, workbench view model, or persistence format changes are needed. The existing `selectedMemberId` remains the source of the visible member; only background shell creation stops mutating it.

## Tests

Add regression coverage for:

1. lazy terminal restoration starts the requested member without changing an already selected member;
2. materializer-driven startup passes non-selecting semantics;
3. explicit member opening retains selecting semantics.

Use the repository test runner (`cd client && dart run tool/run_tests.dart ...`) and run Flutter analysis before completion.

## Scope and non-goals

This change does not alter which members are launched, startup timing, TeamBus delivery, terminal view selection, or explicit member navigation. It only prevents non-explicit startup paths from taking ownership of the current member selection.
