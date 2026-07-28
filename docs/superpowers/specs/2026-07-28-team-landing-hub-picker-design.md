# Team landing hub picker

## Problem

Workspace chat landing in **team mode** exposes a 「选择团队」chip whose menu
lists every local `TeamProfile` and nothing else. Simple mode already offers an
expert chip with recent keys plus 「浏览全部专家」, which opens an Expert
Hub–style picker and applies the selection for launch.

There is no equivalent path from the team chip into **Team Hub** (discover /
clone / select). Users must leave landing, open the sidebar Team Hub, clone,
then return and pick the new local team.

## Goal

Give team-mode landing the same *shape* as the expert landing flow:

1. Team chip menu: recent local teams (≤5) + 「浏览全部团队」.
2. 「浏览全部团队」opens a Team Hub–style dialog where the user can browse
   **My Teams** and **public Team Hub** entries in one page.
3. Confirming an entry resolves to a local `teamId` and selects it for launch
   (reuse an existing clone when possible; otherwise clone then select).

## Non-goals

- Migrating or backfilling older clones that lack provenance (no backward
  compatibility; re-selecting a hub team may create a new local clone).
- Syncing / updating an already-cloned team from the hub.
- Clearing the selected team from the chip (team mode requires a team to
  launch).
- Folding local `TeamProfile` rows into `TeamHubCubit` as synthetic
  `DiscoverableTeam` values.
- Changing sidebar Team Hub page behavior beyond shared widgets reused by the
  picker (clone still goes through `TeamCloneService`).

## Locked decisions

| Topic | Choice |
|-------|--------|
| Product shape | Mirror expert: picker dialog confirms launch selection |
| Chip menu | Recent local teams (≤5) + browse all; **no** clear action |
| Picker content | Single page: My Teams + Team Hub discovery (inline filters, not tabs) |
| Clone policy | If a local team has matching `hubSourceKey`, reuse it; else clone then select |
| Architecture | Keep discovery (`TeamHubCubit`) and launch identities (`LaunchProfileCubit`) separate; compose in a selection use-case + picker UI |
| Provenance | `TeamProfile.hubSourceKey` written on hub clone; hand-built teams leave it null |
| Compatibility | No migration of pre-provenance clones |

## Architecture

```
Landing team chip
  · recent local teamIds (TeamLandingRecentStore)
  · browseAll → showTeamLandingPickerSheet
        │
        ▼
TeamLandingPickerDialog
  · builds TeamLandingEntry list from LaunchProfileCubit + TeamHubCubit
  · filters: mine / discovery / favorites / category
  · detail → Confirm
        │
        ▼
TeamLandingSelection.resolve(...)
  · local id → validate → touch recent → teamId
  · hub key → find by hubSourceKey (earliest if many)
           → else TeamCloneService.clone (sets hubSourceKey)
           → touch recent → teamId
        │
        ▼
Landing: LaunchProfileCubit.selectTeam(teamId) + close dialog
```

### Domain boundaries

| Layer | Owns | Must not |
|-------|------|----------|
| `LaunchProfileCubit` / `TeamProfile` | Launchable local teams; optional `hubSourceKey` | Own Team Hub browse UI |
| `TeamHubCubit` / `DiscoverableTeam` | Public catalog, favorites, clone orchestration entry | Synthesize local profiles into the catalog |
| `TeamLandingSelection` (new use-case) | resolve local-or-hub → `teamId`; clone-or-reuse | Render widgets |
| Landing / picker UI | Chip menu specs, dialog, wiring confirm → selectTeam | Inline clone / dedupe logic |

### Provenance model

- Add `hubSourceKey` on `TeamProfile` (nullable `String?`).
- `TeamCloneService` / team creator path **must** persist the source
  `DiscoverableTeam.key` into the new profile.
- Reuse lookup: `teams.where((t) => t.hubSourceKey == hubKey)`.
- If multiple locals share the same key, pick the earliest by
  `(createdAt asc, sortOrder asc, id asc)` — rule is fixed, not configurable.
- Hand-created teams keep `hubSourceKey == null`.
- No backfill: profiles without the field are treated as having no hub origin.

### Recent store

- New `TeamLandingRecentStore` (mirror `ExpertHubRecentStore`): ordered local
  `teamId` list; store cap 10, chip shows 5.
- Persist at `team-hub/recent.json` via new `AppPaths.teamHubRecentJson`
  (parallel to `member-hub/recent.json` / `team-hub/favorites.json`).
- Touch on successful chip select and on successful picker resolve.

### Picker list model (UI / use-case only)

```text
TeamLandingEntry.local(TeamProfile)
TeamLandingEntry.hub(DiscoverableTeam, { String? localTeamId })
```

- `localTeamId` is set when some local profile’s `hubSourceKey` matches the hub
  key (drives 「已添加」 affordance).
- Default ordering when no source filter: **My Teams first**, then discovery.
- Prefer section headers over a single undifferentiated grid so local vs hub
  card semantics stay clear.
- Search applies to name/description on both sides.
- Discovery-only filters (favorites, category) do not hide My Teams section
  when the source filter is “all”; when source filter is “discovery”, My Teams
  are hidden; when “mine”, hub rows are hidden.

## Chip menu

Pure builder (mirror `buildExpertLandingChipMenuSpecs`):

```
[recent local teams ≤5, current selected]
────────
浏览全部团队
```

- No clear / 「未选择团队」 action.
- Empty locals: menu still exposes browse-all (chip itself stays enabled).
- Chip label: selected team name, or `selectTeam` when none selected.
- Selecting a recent id: `_selectTeam` + recent touch.
- Selecting browse-all: open picker (do not change selection until confirm).

## Picker UX

- Dialog shell mirrors `ExpertLandingPickerDialog` (`TpDialog`, ~960 width,
  grid → detail overlay → Confirm).
- Title: Team Hub title (parity with expert picker using Expert Hub title).
- On open: ensure `TeamHubCubit.load()` if catalog empty.
- Detail:
  - **Local**: roster / capability summary + Confirm → resolve(localId).
  - **Hub**: reuse existing detail content; primary CTA is **确认选用** (not
    only 「克隆为我的团队」). Internally calls resolve(hubKey).
  - Hub entries with `localTeamId` show 「已添加」; Confirm reuses without
    cloning.
- Clone / load errors: toast, keep dialog open, allow retry.
- Partial dep failures on clone: keep success path (team created); toast using
  existing partial-clone copy patterns (`teamHubClonePartial` family).

## Confirm / resolve contract

| Input | Behavior | Result |
|-------|----------|--------|
| Local `teamId` present | Validate → touch recent | `teamId` |
| Hub key with matching `hubSourceKey` | Earliest match → touch recent | existing `teamId` |
| Hub key with no match | Clone (write `hubSourceKey`) → touch recent | new `teamId` |
| Missing local / clone failure | Do not change landing selection | error to UI |

Landing on success: `selectTeam(teamId)`, close dialog, refresh chip label.

## Error handling

- Hub loading: spinner / empty-loading state in grid.
- Clone in flight: disable Confirm; use existing `cloningKeys` spinner.
- Failures: `AppToast` error; dialog stays open.
- Stale local id (deleted underfoot): toast + refresh local list.

## Testing

1. Chip menu builder: recent cap, browse action, no clear, empty-local still
   has browse.
2. `TeamLandingSelection.resolve`: reuse by `hubSourceKey`; first clone writes
   key; multi-match earliest rule; failure leaves selection unchanged.
3. Picker filters: mine / discovery / favorites; 「已添加」 when mapped.
4. Widget: browse opens dialog; confirm updates chip label / selected team id.
5. Recent store: touch ordering and cap.

## Implementation sketch (non-binding file map)

| Area | Likely touch points |
|------|---------------------|
| Model | `TeamProfile` + encode/decode for `hubSourceKey` |
| Clone | `TeamCloneService` / creator wiring to set provenance |
| Use-case | `services/team/team_landing_selection.dart` |
| Recent | `TeamLandingRecentStore` + path helper |
| Chip | `team_landing_chip_menu.dart` + landing `_autoChipSpecs` team branch |
| Picker | `team_landing_picker_sheet.dart` (+ small entry/filter helpers) |
| Landing | `unbound_compose_body.dart` wire browse + resolve |
| l10n | browse-all / confirm / already-added strings (en + zh ARB) |

## Out of scope follow-ups (explicit)

- 「从中心更新已克隆团队」.
- Deep-link from picker card into full-page Team Hub route (optional later).
- Sharing the same recent list with automations team pickers (can adopt the
  store later without redesign).
