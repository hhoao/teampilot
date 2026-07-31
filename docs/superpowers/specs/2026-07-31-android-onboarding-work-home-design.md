# Android onboarding work-home design

**Date:** 2026-07-31  
**Status:** Approved for planning  
**Problem:** Android first-run onboarding includes an SSH step that only **saves** a catalog profile, then a CLI step that needs a **bound** remote work home (`isRemoteWorkPlane`) to detect/install CLIs. Saving does not Connect or `select(...)` home, so CLI detection usually falls through to useless `locateLocal` on the phone. Meanwhile StartupGate already owns Termux | remote SSH Connect → bind. The two surfaces disagree, and the SSH onboarding step is a dead end for the dependency chain.

**Builds on:**  
[2026-07-31-android-termux-home-design.md](./2026-07-31-android-termux-home-design.md) (Termux peer home, Connect → bind, StartupGate predicate).

## Goal

Embed **choose work home + Connect (bind)** as a required Android onboarding step **before** CLI detect/install and later wizard steps, so remote CLI provisioning is meaningful. Keep Connect → `select(...)` as the single bind authority; do not invent a second bind path from “save profile.”

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Where to bind | Inside the first-run wizard (Android), not only post-wizard StartupGate |
| Skip policy | Home step **cannot** be skipped; Next disabled until Connect succeeds and home is bound |
| Appearance | May still be skipped |
| Bind semantics | Unchanged: Connect OK → `HomeTargetController.select(...)` (Termux or `ssh:$id`) |
| Old SSH onboarding step | Remove `OnboardingSshStep` (save-only); replace with work-home step |
| StartupGate after wizard | Remains a safety net (clear setup / unbound home / non-wizard entry); after successful first-run bind it should pass through |
| Desktop | Unchanged (no work-home step in onboarding) |

## Flow

### Android first-run step order

1. **Appearance** — skippable  
2. **Work home** — **not** skippable; blocked until bound  
3. **CLI** — runs with `isRemoteWorkPlane == true` when prior step succeeded  
4. **Provider import**  
5. **Default preset** → complete onboarding  

### Work home step UX

Reuse the two peer paths from the Termux home design, embedded in onboarding chrome (wizard title/subtitle + scroll body; no nested full-screen `Scaffold` that breaks the fixed viewport):

1. **On-device · Termux** → existing guided Termux setup → Connect → `select('termux:default')`  
2. **Remote · SSH** → configure / pick profile → Connect → `select('ssh:$id')` via existing `selectProfileOnConnect`

**Advance rule:** after Connect OK and home bind, **auto-advance** to the CLI step (do not leave the user on a dead Next).

**Failure:** stay on the work-home step; show existing connect/test errors; user may retry or switch peer path.

**Footer:** hide or disable Skip on this step; disable Next until `ConnectionModeService.hasBoundAndroidWorkHome` (or equivalent: home kind is `termux` or `ssh`).

### Relationship to StartupGate

Router remains `OnboardingGate → StartupGate → shell`.

| Scenario | Behavior |
|----------|----------|
| First run, user completes work-home bind in wizard | StartupGate sees bound home → pass |
| Clear setup / home reset to unbound local | StartupGate shows work-environment chooser (existing safety net) |
| Re-open first-run wizard from settings | If home already bound: **skip** the work-home step (do not force a second Connect). Changing home remains via in-app work-environment selector / StartupGate after clear. If unbound: force work-home step |
| User somehow finishes wizard without bind | Must not happen under skip policy; if it did, StartupGate still blocks |

**Invariant:** bind authority is only Connect success → `select(...)`. The wizard does not bind on profile save alone.

## What changes / what does not

**Changes**

- Android `onboardingStepsForPlatform()`: replace `ssh` with a `workHome` (or similarly named) step  
- New onboarding step widget embedding chooser + Termux/SSH connect flows (shared with or wrapping `WorkEnvironmentChooserPage` / setup pages; prefer shared bodies over copy-paste)  
- Wizard footer: per-step Skip/Next gating for work home  
- Remove save-only `OnboardingSshStep` usage from Android wizard  

**Does not change**

- Desktop onboarding step list  
- Termux/SSH Connect implementation and home rebind machinery  
- CLI step logic itself (it already branches on `isRemoteWorkPlane`); it becomes correct once home is bound first  
- Shared-storage migration (out of Termux home plan and this plan)

## Success criteria

1. Android first-run cannot reach the CLI step without a bound Termux or SSH home after a successful Connect.  
2. CLI detect/install on that step uses the remote (SSH/Termux) path, not empty `locateLocal` on the device.  
3. Completing the wizard with a bound home does not re-trap the user in StartupGate chooser.  
4. Clearing Termux/SSH home still returns the user to StartupGate chooser.  
5. Desktop onboarding behavior unchanged.  
6. No bind-on-save: creating an SSH profile without Connect does not satisfy the work-home step.

## Non-goals

- Moving CLI detect out of the wizard  
- Merging OnboardingGate and StartupGate into one widget  
- Changing provider import / default preset semantics beyond ordering after work home  
- Selling cross-home member placement in this flow  
