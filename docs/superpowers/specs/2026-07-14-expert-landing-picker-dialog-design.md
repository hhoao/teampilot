# Expert landing picker dialog

Replace the expert-hub bottom-sheet picker with a centered dialog that mirrors Expert Hub: card grid → detail → Confirm.

## Goal

Landing compose, automation launch config, and team-member “apply expert” all currently open `showExpertLandingPickerSheet` / `showExpertApplyPickerSheet` — a bottom sheet of list tiles where tapping a row selects immediately.

Users expect Expert Hub–style browsing: a dialog, card grid, detail view, and an explicit Confirm before the selection sticks.

## Non-goals

- Changing the Landing expert chip dropdown (Clear / Browse all). Only the “Browse all experts” destination changes.
- Redesigning the full-page Expert Hub route.
- Adding a create-expert flow inside the picker.
- Changing Landing preflight / dependency toast behavior after a key is chosen.

## Entry points (unchanged call sites)

| Caller | API | On confirm |
|--------|-----|------------|
| Landing compose (`workspace_chat_landing.dart`) | `showExpertLandingPickerSheet` | Returns `member.key`; caller runs `_selectExpertWithPreflight` |
| Automation launch section | `showExpertLandingPickerSheet` | Returns `member.key` |
| Team member config / Home team tab | `showExpertApplyPickerSheet` | Invokes `onApply(member)` then closes |

Public function names may stay for compatibility; implementations switch from `showModalBottomSheet` to `showDialog`.

## Interaction

1. User chooses **Browse all experts** from the chip menu (or the equivalent team/automation affordance).
2. App opens a centered `AppDialog` titled with `expertHubTitle`.
3. Dialog shows the Expert Hub card grid (search, filters, sort).
4. Tapping a card navigates **inside the dialog** to expert detail (does **not** select yet).
5. Detail **Confirm** closes the dialog and completes selection/apply as in the table above.
6. Back returns to the grid; dismissing the dialog cancels with no selection change.

## UI composition

### Shell

- `AppDialog` with roughly `maxWidth: 960` and `maxHeight: ~85%` of viewport height.
- Header: Expert Hub title + close.
- Body fills remaining height (list ↔ detail swap).

### List step

- Reuse `ExpertHubBody` against the existing `ExpertHubCubit`.
- Hide the **Create** button (`onCreate: null` and do not show the create control in picker mode — body may need a small `showCreate` flag).
- Tighter inset than the full page.
- On open: if members are empty and status is not loading, call `cubit.load()`.

### Detail step

- Reuse `ExpertHubDetailOverlay` content in a **picker mode**:
  - Primary CTA becomes **Confirm** (new l10n: e.g. `expertHubConfirmSelection` / 确认).
  - Keep favorite toggle.
  - Keep **Add to team** and **Launch in workspace** as secondary actions with the same handlers as the Expert Hub page (via the same callbacks the page already wires). Completing those actions must **not** imply picker confirmation; only Confirm selects.
- Back clears the in-dialog detail and shows the grid again.

### Selected-key highlight

- Landing/automation may pass `selectedKey` so the grid can mark the current expert (same as today’s sheet).

## Data and errors

- Shared `ExpertHubCubit` from the ambient provider tree (dialog builder must have access — callers already sit under the hub cubit).
- Load failures: reuse Expert Hub load-error toast pattern.
- Add-to-team failures inside detail: same toast as Expert Hub page.
- Cancel / barrier dismiss: return `null` (landing) or no `onApply` (apply mode); do not clear an already-selected landing expert.

## File / module sketch

Prefer evolving `expert_landing_picker_sheet.dart` (or renaming to `expert_landing_picker_dialog.dart` with re-exports) rather than scattering new entrypoints:

- `showExpertLandingPickerSheet` / `showExpertApplyPickerSheet` → `showDialog`
- New stateful dialog body: `_detail` member, list/detail switch
- Minimal API tweaks on `ExpertHubBody` / `ExpertHubDetailOverlay` for picker mode (hide create; swap primary CTA)

## Testing

- Widget test: open dialog → tap card → detail visible → Confirm returns key.
- Widget test: open → dismiss / back-out → no selection.
- Widget test: apply mode Confirm invokes `onApply`.
- Widget test: tapping a card alone does not complete selection.
- Update `home_team_tab_add_member_test` to find the new dialog type instead of `ExpertLandingPickerSheet`.

## Out of scope follow-ups

- Deep-linking into a specific expert inside the picker dialog.
- Android-specific sheet fallback (use dialog on all platforms for consistency unless layout proves unusable).
