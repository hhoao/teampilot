# Simple compose: custom CLI / provider / model / effort

**Date:** 2026-07-29  
**Status:** Approved (spec review fixes applied)  
**Product shape:** B2 — preset shortcuts in the model chip menu, plus a **自定义…** entry that configures an explicit four-tuple (not a pure nested ActionMenu cascade).

## Problem

Simple (unteamed) Landing and Continue only pick a global `CliPreset`. Users who want ad-hoc CLI + provider + model + effort must create a preset first. Team member launch already supports custom four-tuples via `CliLaunchCustomFields`; Simple does not.

## Goals

- Landing Simple: choose either a preset **or** an explicit `cli / provider / model / effort` without saving a global preset.
- Continue (**Simple sessions only**): same menu shape; **CLI stays locked**; custom edits provider / model / effort only (or same-CLI presets).
- Persist Landing custom choice in workspace launch prefs so the chip survives restarts.
- Reuse `SimpleLaunchIdentity.resolve` and `CliLaunchCustomFields` — no parallel launch stack.
- Keep Enhance, Ask AI, and submit paths consistent with the same draft / session identity rules.

## Non-goals

- Auto-writing custom choices into `cli-presets.json`
- Changing Team-mode compose chips (**自定义… is not shown for Team Continue**)
- Four-level nested `TpActionMenu` cascade for provider catalogs
- Unlocking CLI on Continue (session CLI lock unchanged)
- Changing Automation rules (still launch via existing preset / params; no new custom four-tuple automation field in this work)

## Data model

Three mutually exclusive Simple draft modes. **Custom vs Empty** is distinguished by **`cli != null`** (not by “any of the four fields”).

| Mode | `presetId` | `cli` | `provider` / `model` / `effort` |
|------|------------|-------|----------------------------------|
| Preset | non-empty | ignored | ignored at submit (from preset) |
| Custom | `null` / cleared | **non-null** (required) | optional; empty provider → official id at resolve |
| Empty | `null` | `null` | empty → today’s default (Claude + official provider) |

### Types to extend

- `LandingLaunchContext` — optional `CliTool? cli`, `String? provider/model/effort`
- `LandingPrefs` / `LandingPrefsStore` JSON — same fields; omit empty / null on write
- `LandingLaunchContext.copyWith` must support **clearing** `presetId` and each four-tuple field (existing `_unset` pattern already used for nullable paths; extend for `presetId` / custom fields so “select preset” and “confirm custom” can null out the other side)

### Transitions

- Select preset → set `presetId`, **clear** `cli/provider/model/effort`
- Confirm custom → set four-tuple (`cli` required), **clear** `presetId` to empty/null (call sites must pass an explicit clear; `AppSession.copyWith` / repo treat null as “keep” today — Continue API must pass `presetId: ''` to clear)
- Clear back to Empty (optional UX): clear both sides; not required for v1 if chip empty state is only “never configured”

### Submit resolve (Landing)

`_resolveSimpleLaunchIdentity` must accept the draft four-tuple, not only `presetId`:

- **Preset:** load `CliPreset`, `SimpleLaunchIdentity.resolve(preset:, expertKey:)` — do not pass conflicting explicit fields
- **Custom (`cli != null`):** `SimpleLaunchIdentity.resolve(cli:, provider:, model:, effort:, presetId: '', expertKey:)`
- **Empty:** existing Claude + official provider fallback

### Continue write path (blocking requirement)

Do **not** call `SessionRepository.updateSimpleLaunchIdentity` alone from UI — that skips in-memory snapshot updates.

Add a Cubit API symmetric to `ChatCubit.setSessionContinuePreset`, e.g. `setSessionContinueCustom`, that:

1. Patches via `SessionContinueOverridesController` (or equivalent)
2. Persists with **`presetId: ''`** to clear provenance
3. Keeps session `cli` unchanged
4. Calls `replaceSessionSnapshot` so the chip updates immediately

Preset Continue path stays `setSessionContinuePreset` (same-CLI only).

## UI

### Model chip menu (Landing Simple)

1. All global presets (existing list; empty hint row if none)
2. Divider
3. **自定义…** → configure surface
4. Add / manage presets (existing) — same divider block as today or one shared divider before both custom + manage; manage remains available even when preset list is empty so Landing can launch via custom alone

### Model chip menu (Continue)

- **Only when `session.isSimple`.** Team Continue: unchanged (same-CLI presets + manage; no **自定义…**).
- Simple Continue:
  1. Same-CLI presets
  2. Divider
  3. **自定义…** → configure surface with CLI locked/hidden
  4. Add / manage presets (`lockCli` when applicable)

### Custom configure surface

- Reuse `CliLaunchCustomFields` (`CliLaunchEffortContext.standalone`)
- Landing seed: current draft (or Claude defaults if Empty)
- Continue seed: session `SimpleLaunchIdentity` / denormalized fields; CLI locked
- Landing: `CliLaunchCliFieldKind.toolList`
- Continue: CLI hidden; provider / model / effort editable
- Confirm writes draft or Cubit continue-custom API; cancel discards (selection unchanged)
- After confirm, **自定义…** is the selected menu affordance

### Chip label

| Surface | Rule |
|---------|------|
| Landing Preset | preset name |
| Landing Custom | `{model}` (fallback `{provider}`); CLI identified by chip leading brand icon only — same pattern as presets showing a name |
| Landing Empty | `workspaceChatLandingUsePreset` |
| Continue + non-empty `presetId` | preset name |
| Continue + empty `presetId` | **session four-tuple summary** (resolved identity is never “Landing empty”) — use custom summary rule, not `workspaceChatLandingUsePreset` |

Chip leading icon: use draft/session `cli` (custom or from selected preset); do not fall back to `presets.first` when custom.

## Enhance

`resolveLandingEnhanceSetting` today keys off `presetId` and otherwise falls back to `presets.firstOrNull`. Extend:

- **Simple custom draft / continue draft:** resolve enhance from the explicit `cli/provider/model/effort` (empty provider → official id), same as launch identity
- **Empty Landing:** keep existing fallback
- **Continue enhance draft** must carry session preset **or** custom four-tuple fields (not only expert/cwd)

## Edge cases

| Scenario | Behavior |
|----------|----------|
| Ask AI dialog | Shares `UnboundComposeBody` + `persistLandingDraft`; custom four-tuple is workspace prefs — no second draft store |
| Simple ↔ Team mode switch | Keep four-tuple in prefs while in Team (ignored on Team submit); switching back to Simple restores prior custom/preset without wiping |
| Expert deep link | `applyExpertDeepLink` / draft `copyWith` must not clear custom four-tuple unless intentionally resetting launch dials |
| Deleted provider/model in catalog | Follow existing “not configured” / launch failure paths; no new toast family |
| Open 自定义… then cancel | Leave prior preset or custom selection unchanged |

## Validation / errors

- No second submit-time configuration wizard
- Confirm on the custom sheet is the gate (Landing requires CLI)
- Incomplete / broken catalogs: existing launch / enhance messaging

## Testing

- Prefs round-trip custom four-tuple; selecting preset clears tuple; confirming custom clears `presetId`
- `copyWith` can clear `presetId` and tuple fields
- `SimpleLaunchIdentity.resolve` for preset vs custom vs empty
- `_resolveSimpleLaunchIdentity` / submit passes custom fields
- Menu includes **自定义…** on Landing Simple and Continue Simple only; Team Continue unchanged
- Continue `setSessionContinueCustom` updates snapshot + persists `presetId: ''`
- Chip labels: Landing empty / custom / preset; Continue never shows Landing empty hint when session has identity
- Enhance: custom draft uses four-tuple; empty Landing keeps fallback
- Ask AI inherits workspace landing prefs after custom save

## File map (expected)

| Area | Likely touch |
|------|----------------|
| Draft / prefs | `landing_launch_context.dart`, `landing_prefs_store.dart`, `landing_draft_resolver.dart` |
| Menu | `compose_model_preset_chip.dart` (+ sentinel for custom) |
| Landing | `unbound_compose_body.dart`, `workspace_session_actions.dart` |
| Continue | `session_chat_view.dart`, `chat_cubit.dart`, `session_continue_overrides_controller.dart` |
| Enhance | `compose_prompt_enhance.dart` (+ Continue draft builders) |
| Dialog | thin host around `CliLaunchCustomFields` |
| Bound chrome | `bound_compose_chrome` / shared menu builder callers as needed |
| l10n | `app_en.arb` / `app_zh.arb` |

## Decision record

- Product: **B** refined to **B2** (presets first, custom entry second)
- Scope: Landing **and** Simple Continue (CLI-locked); Team Continue unchanged
- Implementation: explicit draft four-tuple + configure surface reusing team custom fields; Cubit-symmetric continue custom API; enhance aware of custom
