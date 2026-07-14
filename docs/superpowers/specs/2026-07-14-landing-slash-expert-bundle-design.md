# Landing slash menu mirrors Simple launch expert bundle

Simple-mode Landing `/` suggestions currently omit expert-pack skills/plugins. Launch merges `expert > workspace` via `LayeredConfigBundle`, so users can invoke skills after start that never appeared in the compose picker.

## Goal

Landing (and session-review compose that reuses the same helper) slash enable-lists must use the **same merge layers and expert key** as Simple launch (`expert > workspace`, empty key → builtin default), so every skill/plugin the session would enable after a successful install is selectable in `/` once it is already installed locally.

Parity is intentional at the **layer / key / expectedLocalId** level — not byte-identical to a post-install `runtimeBundle` (launch keeps only successfully installed dep ids; slash lists `expectedLocalId`s and then filters to installed+enabled candidates).

## Non-goals

- Team-mode Landing slash including every roster member’s expert pack (Team still uses team identity + workspace only).
- Triggering skill/plugin install when the user types `/`.
- Changing launch/preflight/provisioning **behavior**. A no-behavior-change extract of expert-key normalization out of `SessionRuntimePlanBuilder` is allowed (and preferred).
- UI redesign of the slash overlay (Skills / Commands sections stay as today).

## Behavior

| Mode | Slash enable bundle |
|------|---------------------|
| Simple | `LayeredConfigBundle.merge(expert: expertDepBundle, workspace: workspaceBundle)` |
| Team | `LayeredConfigBundle.merge(team: teamBundle, workspace: workspaceBundle)` |

### Expert key (Simple only)

Same normalization as `SessionRuntimePlanBuilder`: empty / missing draft `expertKey` → `kBuiltinDefaultExpertKey`. Prefer extracting a shared `normalizeLandingExpertKey` (or equivalent) so Landing slash and launch cannot drift.

### Expert dep bundle (no install)

1. Sync-resolve the expert via `ExpertMemberResolver.resolve` (hub catalog + builtins).
2. Build `ConfigBundle` from `skillDeps` / `pluginDeps` `expectedLocalId` values. Optionally include `mcpDeps` local ids the same way launch would for bundle shape completeness; slash UI only reads skill/plugin ids today.
3. Unknown expert key → empty expert layer (workspace-only), do not throw.

Candidates still pass through `buildComposeSlashCandidates`, which only surfaces **installed + enabled** skills and enabled plugin commands whose ids are in the bundle. Uninstalled deps therefore stay invisible until preflight/launch installs them — consistent with today’s installed-only slash filter.

## API break (no backward compatibility)

Replace `identityBundleForLanding` and `unionConfigBundles` in `compose_landing_bundle.dart` with a single entrypoint, e.g.:

```dart
ConfigBundle slashBundleForLanding({
  required LandingLaunchContext draft,
  TeamProfile? team,
  required ConfigBundle workspace,
  ExpertHubState? hubState,
})
```

Call sites:

- `workspace_chat_landing.dart` (`_slashBundleForDraft`)
- `session_history_review.dart` (`_slashBundle`)

Delete the old helpers; update tests that reference them.

## Data flow

```
Landing draft (isPersonal, expertKey, teamId)
  → slashBundleForLanding
      → Simple: normalize key → ExpertMemberResolver → dep ids
      → Team: team.skillIds / pluginIds / mcpServerIds
  → LayeredConfigBundle.merge(...)
  → ComposeTriggerField.slashBundle
  → buildComposeSlashCandidates(skills, plugins, enabledBundle)
```

## Errors

- Missing catalog member: empty expert layer; slash still works with workspace ids.
- Hub state not loaded yet: builtins still resolve for builtin keys; custom experts may briefly omit deps until hub load completes (same as other Landing expert UI).

## Testing

- Unit: Simple + explicit expert includes that expert’s `expectedLocalId`s union workspace.
- Unit: Simple + empty expertKey uses default expert deps.
- Unit: Team mode ignores draft expertKey; uses team + workspace only.
- Unit: unknown expert key → workspace-only.
- Update / replace `unionConfigBundles` tests in `compose_trigger_query_test.dart` (or move to a dedicated `compose_landing_bundle_test.dart`).

## File sketch

| File | Change |
|------|--------|
| `client/lib/services/compose/compose_landing_bundle.dart` | New `slashBundleForLanding`; remove old helpers |
| Shared expert-key normalize (plan builder or small util) | Extract empty → default key |
| `workspace_chat_landing.dart` | Wire hub state + new API |
| `session_history_review.dart` | Same |
| `client/test/services/compose/…` | Cover matrix above |
