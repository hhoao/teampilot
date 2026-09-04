# Generate settings: inline four-tuple pool + LaunchFourTuplePicker

**Date:** 2026-09-03  
**Status:** Approved for planning  
**Related:** [2026-08-31-agentic-team-generate-launch-design.md](./2026-08-31-agentic-team-generate-launch-design.md)

## Problem

Generate-and-launch settings currently:

1. Restrict the **model configuration pool** to saved CLI presets (`presetId` only).
2. Configure the **generator model** with the AI Features form (`AiFeatureConfigurePanel`), not the Simple-mode cascade menu users already know.
3. In native mode, the native CLI control was corrected to `nativeTeamLaunchable`, but pool/generator pickers still need the same CLI filter when choosing models.

Users want both pool entries and the generator to work like the Simple compose cascade: presets as shortcuts, custom models allowed, values stored as concrete launch four-tuples.

## Goals

- Pool entries store **inline** `cli / provider / model / effort` (plus description/tags), not a live preset binding.
- Selecting a preset **snapshots** into that four-tuple immediately.
- Generator model uses the **same picker UX** and saves as inline `AiFeatureSetting` with `activePresetId: null`.
- Landing submit / coordinator preflight resolve that inline setting (not a global preset id) into the builder `SimpleLaunchIdentity`.
- Native team mode: **model-pool** pickers only expose the frozen/selected `nativeCli`. The **generator** picker stays on all launchable CLIs (it builds the plan; it is not a roster member).
- Extract a reusable **`LaunchFourTuplePicker`** so settings (and later Simple compose) share one control.

## Non-goals

- Migrating the Simple landing compose chip to the new picker in this change (follow-up OK).
- “Save as preset” from pool/generator pickers in this change.
- Redesigning other AI Features rows beyond `teamGenerate` usage inside generate settings.
- Changing Team Composer tool count or the overall generate-and-launch workflow.

## Decisions

| Topic | Choice |
|-------|--------|
| Custom pool values | Inline four-tuple (no required named preset) |
| Preset selection | Snapshot at pick time; do not keep `activePresetId` / live bind |
| Generator storage | Same inline four-tuple into `AiFeatureId.teamGenerate` |
| UI approach | Extract `LaunchFourTuplePicker` wrapping existing cascade menu helpers |
| Native CLI filter | Pool `cliItems = [nativeCli]` when `teamMode == native`; generator unrestricted among launchable |
| Plan wire field | Keep member `presetId` name; meaning = frozen pool entry `id` |

## Data model

### `GenerateModelPoolEntry`

Persist:

- `id` — stable pool-entry id (UUID or equivalent for new rows)
- `cli`, `provider`, `model`, `effort` (effort may be empty)
- `description`, `tags` (unchanged)

Remove `presetId` as source of truth.

### Load migration

If JSON still has only `presetId`:

1. Resolve against current global presets.
2. If found: snapshot four-tuple; set `id = presetId`.
3. If missing: drop the entry from the effective pool (same as today).

After save, write only the inline shape.

### Effective snapshot / context

`EffectiveGenerateModelPoolEntry` carries the resolved four-tuple (and source metadata).  
`get_generation_context.modelPool[]` exposes:

```text
rank, id, cli, provider, model, effort, description, tags
```

`id` occupies the former `presetId` slot for builders. It need not exist in `CliPresetsCubit`.

### Generator

On save from generate settings:

- `AiFeatureSetting(activePresetId: null, cli, providerId, model, effort)`
- Configuration validity continues to use `aiFeatureIsConfigured`.

## UI: `LaunchFourTuplePicker`

**Location:** `client/lib/widgets/cli_launch_config/` (or adjacent shared compose helpers).

**Inputs:**

- Current value: four-tuple (nullable / incomplete = unconfigured)
- `cliItems`: allowed CLIs
- `presets`: shortcut list only
- Flags: `showManagePresets` (yes in settings); `showSavePreset` (no for this change)

**Output:** `onChanged(SimpleLaunchFourTuple)` (or identical type).  
Custom model id continues via `CascadeCustomModelRequest` + small dialog.

**Presentation:** Chip-like trigger (CLI icon + summary label), menu built from `resolveComposeCascadeCliGroups` + `buildComposeModelCascadeMenuSpecs` (add a `showSavePreset` parameter if needed).

**Call sites (this change):**

1. Generator section in `workspace_landing_generate_settings_dialog.dart` — replace `AiFeatureConfigurePanel`.
2. Each model-pool row — replace preset-only `TpSelect`; “add” opens picker then appends a row with a new `id`.

Simple compose is **not** required to switch in this PR.

### Native mode

- When `teamMode == native`, **pool** picker `cliItems = [nativeCli]`.
- Generator picker always uses launchable CLIs (not tied to native mode).
- Changing `nativeCli` keeps existing hide/effective-pool filtering for non-matching rows.
- Native CLI dropdown remains limited to `registry.nativeTeamLaunchable`.

## Validation & skill contract

- Index frozen pool by entry `id`.
- Member `presetId` must reference a frozen pool `id` (empty → inherit rank 1).
- Digests hash the entry four-tuple (not live global presets). Mid-run settings edits still gated by `settingsRevision`.
- Native: every referenced entry’s `cli` must equal frozen `nativeCli`.
- Update `team-builder` skill / plan schema docs: select only context pool ids; do not invent global preset names.

## Compatibility

- Old settings files with `presetId`-only pool rows migrate on load as above.
- Generated plan JSON keeps the `presetId` field name for members.
- Existing workflows mid-flight: prefer revision mismatch / recovery paths already present; no need to rewrite in-flight plan files beyond current revision checks.

## Testing

- Model JSON round-trip: legacy `presetId` → inline; new inline → same.
- Snapshot/effective pool: native filter; missing legacy preset dropped.
- Validator: accepts pool entry ids; rejects unknown ids; native CLI mismatch.
- Dialog/widget tests: picker emits four-tuple; native `cliItems` length 1; generator save clears `activePresetId`.

## Success criteria

- Pool can add a custom model without creating a named preset.
- Native mode cannot pick another CLI in **pool** pickers; generator may still use any launchable CLI.
- Generator uses the cascade picker and persists inline config.
- Legacy settings load; generate flow still validates against frozen pool ids.
