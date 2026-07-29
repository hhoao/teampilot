# Android SSH startup: land on list, exit add form

**Date:** 2026-07-29  
**Status:** Approved (option A / approach 1)

## Problem

On Android first launch (no SSH home / no profiles), `StartupGate` replaces the app with `SshProfileSetupPage` (“新增 SSH Profile”). That page is not on a `Navigator` stack, so:

- There is no back / cancel exit.
- Save does not leave the page reliably (gate callback never `pop`s; auto-select home may fail to clear the gate from the user’s perspective).

Users expect the **SSH list** first, and the add form to be a dismissible sub-page.

## Decision

`StartupGate` shows **`SshProfilesPage`** (list) when SSH setup is required. Adding / editing a profile is a pushed route. Save and back both return to the list. Entering the main app happens only after the user **Connect**s a profile.

**Important:** today’s Android `selectProfileOnConnect` only calls `SshProfileCubit.selectProfile` (persists `selectedProfileId`). It does **not** call `HomeTargetController.select('ssh:…')`. The gate currently clears only because setup-save does that home switch. This change moves the home switch onto **Connect**, so the gate can clear after the user connects from the list.

## Behavior

| Path | Change |
|------|--------|
| `StartupGate` when `requiresSshProfileSetup` or `androidNeedsSshHome` | Render `SshProfilesPage` instead of `SshProfileSetupPage` |
| Add / edit from list (`openSshProfileEditor` on Android) | Unchanged: `Navigator.push` → setup page; AppBar back works |
| Save on setup page (pushed) | Reload profiles + `maybePop` back to list; **do not** auto-select home |
| Android Connect (`selectProfileOnConnect`) | After a successful connect: `HomeTargetController.select('ssh:$id')` **and** `SshProfileCubit.selectProfile(id)` so home becomes SSH and selected-profile persistence stays intact |
| Gate clear | Same predicates as today (`requiresSshProfileSetup` / `androidNeedsSshHome`). Cleared when home is SSH and profiles exist — which now happens via Connect, not via save |
| Desktop same gate | Same list host if the gate fires; desktop Connect need not switch home unless product already does |

## Non-goals

- Requiring an extra “connected” status beyond existing gate / Connect semantics
- Routing cold start through `/config/ssh-profiles` settings chrome
- Redesigning the add-form fields or auth UI
- Changing onboarding wizard SSH step (`OnboardingSshStep`) in this change

## Implementation notes

- Remove the gate’s inline `SshProfileSetupPage` + `onProfileSaved` home `select` path.
- Wire Android `selectProfileOnConnect` so Connect switches home to `ssh:$id` (and keeps selected-profile persistence if still needed).
- Keep `SshProfilesPage` / `openSshProfileEditor` as the single Android editor entry.
- Tests: gated startup builds the list (not bare setup title); push add + pop returns to list; local home → add profile → Connect → gate dismisses.
