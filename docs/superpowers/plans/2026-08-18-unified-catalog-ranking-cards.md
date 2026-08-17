# Unified Catalog Ranking and Install Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independent adoption-first ranking, shared install-oriented cards, optional catalog metrics, and partial-source failure handling to Skills, MCP, plugins, teams, and experts.

**Architecture:** Add a domain-neutral catalog contract in `client/lib/models/catalog/` and pure sorting/aggregation services in `client/lib/services/catalog/`. Each resource adapts its own model into the contract while retaining its own install, add, clone, dependency, and favorite behavior. Shared visual primitives live in `client/packages/shared_ui`; resource pages compose those primitives instead of importing domain cubits into shared UI.

**Tech Stack:** Dart, Flutter, flutter_bloc, Equatable, shared_ui `Tp*` components, Flutter widget tests, JSON catalog manifests, injected HTTP/filesystem test doubles.

## Global Constraints

- Each resource type has its own catalog and ranking; no cross-resource leaderboard is introduced.
- Default sort is adoption/popularity descending; missing values sort after present values.
- Stable ties use updated timestamp descending, then case-insensitive name ascending.
- All catalog timestamps use epoch milliseconds at the catalog boundary.
- Missing metrics render as `—`; no local count is presented as a public remote metric.
- A failed source never hides successful entries; failures appear beside refresh in a hover tooltip.
- Only full failure with no entries renders the blocking error state.
- Shared UI contains presentation primitives only and never imports app cubits or domain repositories.
- Existing page-specific sort enums and all-or-nothing discovery error presentation may be replaced; backward compatibility is not required.
- Every implementation task follows red-green-refactor: write a failing test, run it and observe the expected failure, implement the smallest change, run the focused test, then run affected tests.
- Preserve unrelated dirty worktree changes; stage only files belonging to this feature.

---

## File Map

### Create

- `client/lib/models/catalog/catalog_types.dart` — resource kind, sort keys, metrics, entry, query, source failure, source result, aggregate types, and adapters.
- `client/lib/services/catalog/catalog_sort_comparator.dart` — null-aware stable comparator and typed list sorting helper.
- `client/lib/services/catalog/catalog_source_aggregation.dart` — source-result merge and failure aggregation.
- `client/lib/services/catalog/catalog_error_sanitizer.dart` — remove credentials, authorization values, and raw response bodies before tooltip display.
- `client/test/services/catalog/catalog_sort_comparator_test.dart` — pure sorting and timestamp tests.
- `client/test/services/catalog/catalog_source_aggregation_test.dart` — partial-success and all-failure tests.
- `client/test/services/catalog/catalog_error_sanitizer_test.dart` — sanitized failure-message tests.
- `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_card_shell.dart` — generic card frame.
- `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_metadata_row.dart` — four-slot metric row and missing-value presentation.
- `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_sort_control.dart` — generic sort select wrapper.
- `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_source_warning.dart` — warning icon and tooltip view.
- `client/packages/shared_ui/test/components/catalog/tp_catalog_card_shell_test.dart` — shared card layout test.
- `client/packages/shared_ui/test/components/catalog/tp_catalog_metadata_row_test.dart` — metric and `—` rendering tests.
- `client/packages/shared_ui/test/components/catalog/tp_catalog_source_warning_test.dart` — warning visibility and tooltip tests.

### Modify: models and catalog mapping

- `client/lib/models/skill.dart` — add optional metrics to `DiscoverableSkill` and normalize its catalog statistics.
- `client/lib/services/skill/marketplace/skill_marketplace_source.dart` — replace source-specific public metric fields with catalog metrics and labels.
- `client/lib/services/skill/registry/api_registry_source.dart` — map SkillsMP and skills.sh response statistics into metrics.
- `client/lib/services/skill/skills_sh_service.dart` — return normalized timestamp/count values required by the adapter.
- `client/lib/models/mcp_catalog_listing.dart` — add optional catalog metrics and JSON serialization.
- `client/lib/services/mcp/mcp_catalog_mapper.dart` — map official and Smithery statistics into metrics.
- `client/lib/models/discoverable_team.dart` — add optional metrics and parse/serialize `metrics`.
- `client/lib/models/discoverable_member.dart` — add optional metrics and parse/serialize `metrics`.
- `client/lib/models/plugin.dart` — add optional metrics to `DiscoverablePlugin` and parse/serialize marketplace data.
- `client/lib/services/plugin/plugin_repo_service.dart` — preserve marketplace metrics when loading discoverable plugins.
- `team-hub/teams/gstack-req-dev/team.json` — include the explicit empty metrics object in the registry manifest example.
- `member-hub/members/gstack-developer/member.json` — include the explicit empty metrics object in the registry manifest example.

### Modify: shared UI exports and localization

- `client/packages/shared_ui/lib/shared_ui.dart` — export the four catalog primitives.
- `client/lib/l10n/app_en.arb` — add sort labels, metric labels, no-data text, source-warning text, and accessibility labels.
- `client/lib/l10n/app_zh.arb` — add Chinese translations for the same keys.
- Generated `client/lib/l10n/app_localizations*.dart` files — regenerate with the repository’s Flutter localization command.

### Modify: Skills

- `client/lib/cubits/skill_cubit.dart` — replace global discovery error behavior with per-source failures, add `CatalogSortKey` state, sort merged results, and retain entries during refresh.
- `client/lib/pages/skills/skill_discovery_section.dart` — add sort control/source warning, keep successful cards visible on partial failure, and show full error only when there are no entries.
- `client/lib/pages/skills/marketplace_skill_card.dart` — compose the shared card shell and metadata row while preserving GitHub details and install/add-repository actions.
- `client/lib/pages/skills/skill_discovery_helpers.dart` — adapt and sort unified entries through the catalog contract.
- `client/test/pages/skills/skill_discovery_section_test.dart` — replace all-or-nothing expectation with partial-success, warning, sorting, and placeholder coverage.
- `client/test/cubits/skill_cubit_test.dart` — add source-result aggregation and default sort tests where the existing cubit test harness permits.

### Modify: MCP

- `client/lib/cubits/mcp_discovery_cubit.dart` — add per-source failures and `CatalogSortKey`, load Smithery/official sources independently, retain cached entries during refresh, and sort the merged active view.
- `client/lib/pages/mcp/mcp_discovery_section.dart` — add search/sort/refresh/warning toolbar and partial-result rendering.
- `client/lib/pages/mcp/mcp_shared_widgets.dart` — convert `McpCatalogListingTile` to the shared catalog card layout and metadata row while preserving verification, homepage, and add behavior.
- `client/test/cubits/mcp_discovery_cubit_test.dart` — add partial-source, all-source, sorting, and refresh-retention tests.
- `client/test/pages/mcp/mcp_discovery_section_test.dart` — add toolbar, warning tooltip, metric placeholder, and add-action tests.

### Modify: plugins

- `client/lib/cubits/plugin_cubit.dart` — add catalog sort and per-marketplace failure state, sort discoverables with the shared comparator, and retain successful marketplace entries.
- `client/lib/pages/plugins/plugin_discovery_section.dart` — add sort control/source warning and render the grid/list with partial results.
- `client/lib/pages/plugins/plugin_management_cards.dart` — refactor `PluginDiscoverableCard` to use the shared card shell and metadata row.
- `client/test/cubits/plugin_cubit_test.dart` — cover default adoption sorting, missing metrics, and partial marketplace failure.
- `client/test/pages/plugins/plugin_discovery_section_test.dart` — cover sort control, warning tooltip, placeholders, and install action.

### Modify: teams and experts

- `client/lib/cubits/team_hub_cubit.dart` — replace `TeamSort` with `CatalogSortKey`, sort via the shared comparator, retain cached entries on refresh failure, and expose registry failure records.
- `client/lib/pages/team_hub/team_hub_body.dart` — add all five sort choices, source warning beside refresh, and pass catalog metadata into cards.
- `client/lib/pages/team_hub/team_hub_cards.dart` — use the shared card shell and metadata row while preserving favorite and clone affordances.
- `client/lib/services/team_hub/team_hub_source.dart` — expose source identity for failure records.
- `client/lib/services/team_hub/git_registry_team_hub_source.dart` — distinguish an empty valid catalog from a failed network fetch and preserve cached data on refresh failure.
- `client/lib/cubits/expert_hub_cubit.dart` — replace `MemberSort` with `CatalogSortKey`, sort via the shared comparator, retain cached entries on refresh failure, and expose registry failure records.
- `client/lib/pages/expert_hub/expert_hub_body.dart` — add all five sort choices and source warning beside refresh.
- `client/lib/pages/expert_hub/expert_hub_cards.dart` — use the shared card shell and metadata row while preserving source badges and add behavior.
- `client/lib/services/expert_hub/expert_hub_source.dart` — expose source identity for failure records.
- `client/lib/services/expert_hub/git_registry_expert_hub_source.dart` — distinguish an empty valid catalog from a failed network fetch and preserve cached data on refresh failure.
- `client/test/cubits/team_hub_cubit_test.dart` — cover adoption default, all sort keys, null ordering, and refresh failure retention.
- `client/test/cubits/expert_hub_cubit_test.dart` — cover adoption default, all sort keys, null ordering, and refresh failure retention.
- `client/test/pages/team_hub/team_hub_body_test.dart` — cover sort options, source warning, metadata placeholders, and clone action.
- `client/test/pages/expert_hub/expert_hub_body_test.dart` — cover sort options, source warning, metadata placeholders, and add action.

### Modify: integration and documentation

- `client/test/pages/skills/skill_discovery_section_test.dart` — use the shared warning and metric test fixtures.
- `client/test/pages/mcp/mcp_discovery_section_test.dart` — use the shared warning and metric test fixtures.
- `docs/workspace-storage-layout.md` — document any catalog cache/schema changes if the migrated snapshots store the new metrics.
- `docs/superpowers/specs/2026-08-18-unified-catalog-ranking-cards-design.md` — update only if implementation resolves a documented ambiguity; do not broaden scope.

---

## Task 1: Build the catalog contract and pure sorting/aggregation services

**Files:**

- Create: `client/lib/models/catalog/catalog_types.dart`
- Create: `client/lib/services/catalog/catalog_sort_comparator.dart`
- Create: `client/lib/services/catalog/catalog_source_aggregation.dart`
- Create: `client/lib/services/catalog/catalog_error_sanitizer.dart`
- Test: `client/test/services/catalog/catalog_sort_comparator_test.dart`
- Test: `client/test/services/catalog/catalog_source_aggregation_test.dart`
- Test: `client/test/services/catalog/catalog_error_sanitizer_test.dart`

**Interfaces:**

- `CatalogMetrics` carries nullable `adoptionCount`, `rating`, `ratingCount`, `updatedAtMs`, and `publishedAtMs`.
- `CatalogEntry` carries `id`, `kind`, `name`, `description`, `sourceLabel`, `author`, `tags`, and `metrics`.
- `CatalogAdapter<T>.adapt(T item)` returns a `CatalogEntry`.
- `CatalogSortComparator.compare(CatalogEntry a, CatalogEntry b, CatalogSortKey key)` returns a deterministic comparator result.
- `CatalogSourceResult<T>` carries `sourceId`, `sourceLabel`, `items`, `hasNext`, and an optional `CatalogSourceFailure`.
- `CatalogSourceAggregator.merge<T>(Iterable<CatalogSourceResult<T>> results, CatalogAdapter<T> adapter, CatalogSortKey sort)` returns `CatalogAggregate<T>` with successful items sorted and failures preserved.
- `CatalogAggregate<T>` carries `items`, `hasNextBySource`, and `failures`.

- [ ] **Step 1: Write failing pure tests**

Add tests with entries whose adoption, rating, updated, and published values are present, null, and tied. Assert adoption is descending by default, null values are last, ties use updated descending then case-insensitive name ascending, source aggregation returns successful items plus every failure, and the sanitizer removes bearer tokens, API keys, and response-body fragments.

- [ ] **Step 2: Run the focused tests and verify the expected failure**

Run:

```bash
cd client
flutter test test/services/catalog/catalog_sort_comparator_test.dart test/services/catalog/catalog_source_aggregation_test.dart test/services/catalog/catalog_error_sanitizer_test.dart
```

Expected: compilation/test failure because the catalog types, comparator, aggregator, and sanitizer do not exist yet.

- [ ] **Step 3: Implement the minimal catalog types and comparator**

Implement immutable types, `CatalogErrorSanitizer.sanitize(String message)`, and this comparator contract:

```dart
static int compare(CatalogEntry a, CatalogEntry b, CatalogSortKey key) {
  if (key == CatalogSortKey.name) {
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (name != 0) return name;
    return _compareNullableNumbers(
      a.metrics.updatedAtMs,
      b.metrics.updatedAtMs,
      descending: true,
    );
  }
  final primary = _compareNullableNumbers(
    _value(a.metrics, key),
    _value(b.metrics, key),
    descending: true,
  );
  if (primary != 0) return primary;
  final updated = _compareNullableNumbers(
    a.metrics.updatedAtMs,
    b.metrics.updatedAtMs,
    descending: true,
  );
  if (updated != 0) return updated;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
```

Use an explicit name branch so names sort ascending and do not pass through numeric null handling. Keep source aggregation independent of Flutter and cubits.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run:

```bash
cd client
flutter test test/services/catalog/catalog_sort_comparator_test.dart test/services/catalog/catalog_source_aggregation_test.dart test/services/catalog/catalog_error_sanitizer_test.dart
```

Expected: all catalog comparator, aggregation, and sanitization tests pass.

- [ ] **Step 5: Commit the foundational contract**

```bash
git add client/lib/models/catalog client/lib/services/catalog client/test/services/catalog
git commit -m "feat: add catalog ranking contract"
```

## Task 2: Add shared catalog card, metadata, sort, and warning primitives

**Files:**

- Create: `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_card_shell.dart`
- Create: `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_metadata_row.dart`
- Create: `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_sort_control.dart`
- Create: `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_source_warning.dart`
- Modify: `client/packages/shared_ui/lib/shared_ui.dart`
- Test: `client/packages/shared_ui/test/components/catalog/tp_catalog_card_shell_test.dart`
- Test: `client/packages/shared_ui/test/components/catalog/tp_catalog_metadata_row_test.dart`
- Test: `client/packages/shared_ui/test/components/catalog/tp_catalog_source_warning_test.dart`

**Interfaces:**

- `TpCatalogCardShell` accepts `title`, `source`, `description`, `Widget metadata`, `Widget action`, optional `leading`, and optional `body`.
- `TpCatalogMetricView` carries an icon, label, value, and missing-value tooltip.
- `TpCatalogMetadataRow` accepts exactly four `TpCatalogMetricView` values and wraps them for narrow layouts.
- `TpCatalogSortControl<T>` accepts `items`, `initialItem`, `itemLabel`, and `onChanged` and delegates to `TpSelect<T>`.
- `TpCatalogSourceWarning` accepts immutable `List<TpCatalogFailureView>` and renders nothing when empty; otherwise it renders a warning icon with a newline-separated tooltip.

- [ ] **Step 1: Write failing shared-ui widget tests**

Assert the shell renders title, source, description, metadata, and action; metadata renders all four slots and `—`; sort control renders the selected label; warning is absent for an empty list and its tooltip contains source labels and errors for non-empty input.

- [ ] **Step 2: Run shared-ui tests and verify failure**

```bash
cd client/packages/shared_ui
flutter test test/components/catalog/tp_catalog_card_shell_test.dart test/components/catalog/tp_catalog_metadata_row_test.dart test/components/catalog/tp_catalog_source_warning_test.dart
```

Expected: failure because the catalog primitives do not exist.

- [ ] **Step 3: Implement the primitives and export them**

Keep the package independent from `teampilot` models and localization. Receive already-localized strings and failure view data from the app. Use `Tooltip` around the warning icon and `LayoutBuilder`/`Wrap` for narrow widths.

- [ ] **Step 4: Run shared-ui tests and verify pass**

Run the same command. Expected: all three widget test files pass.

- [ ] **Step 5: Commit shared UI**

```bash
git add client/packages/shared_ui/lib/src/components/catalog client/packages/shared_ui/lib/shared_ui.dart client/packages/shared_ui/test/components/catalog
git commit -m "feat: add shared catalog card primitives"
```

## Task 3: Migrate catalog metrics and localization

**Files:**

- Modify: `client/lib/models/skill.dart`
- Modify: `client/lib/services/skill/marketplace/skill_marketplace_source.dart`
- Modify: `client/lib/services/skill/registry/api_registry_source.dart`
- Modify: `client/lib/services/skill/skills_sh_service.dart`
- Modify: `client/lib/models/mcp_catalog_listing.dart`
- Modify: `client/lib/services/mcp/mcp_catalog_mapper.dart`
- Modify: `client/lib/models/discoverable_team.dart`
- Modify: `client/lib/models/discoverable_member.dart`
- Modify: `client/lib/models/plugin.dart`
- Modify: `client/lib/services/plugin/plugin_repo_service.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/models/catalog/catalog_metrics_serialization_test.dart`
- Test: `client/test/services/skill/skill_catalog_metrics_mapping_test.dart`
- Test: `client/test/services/mcp/mcp_catalog_metrics_mapping_test.dart`
- Test: `client/test/services/team_hub/catalog_metrics_mapping_test.dart`
- Test: `client/test/services/expert_hub/catalog_metrics_mapping_test.dart`
- Test: `client/test/services/plugin/catalog_metrics_mapping_test.dart`

**Interfaces:**

- Each public/discoverable model has `CatalogMetrics metrics` with `const CatalogMetrics()` as the missing-data default.
- JSON uses the `metrics` object with `adoptionCount`, `rating`, `ratingCount`, `updatedAtMs`, and `publishedAtMs`.
- `MarketplaceSkill` maps skills.sh installs to `adoptionCount`; it maps explicit SkillsMP rating data only and never maps GitHub stars to rating.
- MCP maps `useCount` to `adoptionCount` and explicit source rating fields only.
- Existing second-based skill timestamps are converted once to milliseconds by the source adapter.
- Team, expert, and plugin records preserve null metrics through local cache and remote manifest parsing.

- [ ] **Step 1: Write failing serialization and adapter tests**

Test a full metrics object round-trip, an omitted metrics object producing null fields, seconds-to-milliseconds conversion for Skills, `useCount` mapping for MCP, and null metrics for team/expert/plugin fixtures.

- [ ] **Step 2: Run focused mapping tests and verify failure**

```bash
cd client
flutter test test/models/catalog/catalog_metrics_serialization_test.dart test/services/skill/skill_catalog_metrics_mapping_test.dart test/services/mcp/mcp_catalog_metrics_mapping_test.dart test/services/team_hub/catalog_metrics_mapping_test.dart test/services/expert_hub/catalog_metrics_mapping_test.dart test/services/plugin/catalog_metrics_mapping_test.dart
```

Expected: failure because models and mappers do not expose the new metrics contract.

- [ ] **Step 3: Implement model/schema migration and localized labels**

Replace page-specific public metric fields with `CatalogMetrics`, update all affected call sites, add the English and Chinese strings for sort choices, metric labels, missing metrics, source failures, and accessibility descriptions, then regenerate localization files with:

```bash
cd client
flutter gen-l10n
```

- [ ] **Step 4: Run focused mapping tests and verify pass**

Run the same test command. Expected: all serialization and adapter tests pass.

- [ ] **Step 5: Commit the data contract migration**

```bash
git add client/lib/models client/lib/services/skill client/lib/services/mcp client/lib/services/plugin client/lib/l10n
git commit -m "feat: add normalized catalog metrics"
```

## Task 4: Migrate Skills discovery to partial results and adoption-first sorting

**Files:**

- Modify: `client/lib/cubits/skill_cubit.dart`
- Modify: `client/lib/pages/skills/skill_discovery_section.dart`
- Modify: `client/lib/pages/skills/marketplace_skill_card.dart`
- Modify: `client/lib/pages/skills/skill_discovery_helpers.dart`
- Modify: `client/test/pages/skills/skill_discovery_section_test.dart`
- Modify: `client/test/cubits/skill_cubit_test.dart`

**Interfaces:**

- `SkillState` stores `CatalogSortKey discoverySort` and `List<CatalogSourceFailure> discoveryFailures`.
- `SkillCubit.unifiedSearch` emits successful entries and failures independently; it never sets a blocking discovery error when entries exist.
- `SkillCubit.setDiscoverySort(CatalogSortKey sort)` reorders the current merged entries without another network request when all needed metrics are already loaded.
- `SkillDiscoverySection` shows `TpCatalogSortControl<CatalogSortKey>` and `TpCatalogSourceWarning` beside refresh.

- [ ] **Step 1: Write failing cubit and widget tests**

Extend the existing fake sources with one successful source and one throwing source. Assert the successful card remains visible, `discoveryFailures` contains the failed source, the warning tooltip contains its label and message, default order is adoption descending, changing sort reorders entries, and all-source failure with no entries still shows retry/error UI.

- [ ] **Step 2: Run Skills tests and verify failure**

```bash
cd client
flutter test test/pages/skills/skill_discovery_section_test.dart test/cubits/skill_cubit_test.dart
```

Expected: the old generic error-card assertions fail for the new partial-result expectation, and the new sort/warning assertions fail.

- [ ] **Step 3: Implement Skills aggregation, toolbar, and card composition**

Use `CatalogSourceAggregator` for `unifiedSearch`, preserve entries while `discoveryLoading` is true, sort with the shared comparator, and render the error card only when `entries.isEmpty && failures.isNotEmpty`. Refactor `MarketplaceSkillCard` to use `TpCatalogCardShell` and four metric slots while retaining details and install/add-repository actions.

- [ ] **Step 4: Run Skills tests and verify pass**

Run the same command. Expected: all existing and new Skills discovery tests pass.

- [ ] **Step 5: Commit Skills integration**

```bash
git add client/lib/cubits/skill_cubit.dart client/lib/pages/skills client/test/pages/skills/skill_discovery_section_test.dart client/test/cubits/skill_cubit_test.dart
git commit -m "feat: make skills discovery partial and sortable"
```

## Task 5: Migrate MCP discovery to independent source results and shared cards

**Files:**

- Modify: `client/lib/cubits/mcp_discovery_cubit.dart`
- Modify: `client/lib/pages/mcp/mcp_discovery_section.dart`
- Modify: `client/lib/pages/mcp/mcp_shared_widgets.dart`
- Modify: `client/test/cubits/mcp_discovery_cubit_test.dart`
- Modify: `client/test/pages/mcp/mcp_discovery_section_test.dart`

**Interfaces:**

- `McpDiscoveryState` stores `CatalogSortKey sort` and `List<CatalogSourceFailure> sourceFailures` while retaining separate Smithery and official item caches.
- Smithery and official refreshes update their own cache and failure independently; a failure never clears the other source’s entries.
- `McpDiscoveryCubit.setSort(CatalogSortKey sort)` sorts the active merged view through the shared comparator.
- MCP cards use the shared shell with `uses` as the adoption label and preserve verified, remote, tags, homepage, and add action.

- [ ] **Step 1: Write failing MCP tests**

Use injected Smithery/official fakes where one source succeeds and one throws. Assert successful items remain visible, warning state identifies the failed source, sort options reorder the merged list, refresh retains old entries while loading, and all-source failure with an empty cache renders the existing retry/empty path.

- [ ] **Step 2: Run MCP tests and verify failure**

```bash
cd client
flutter test test/cubits/mcp_discovery_cubit_test.dart test/pages/mcp/mcp_discovery_section_test.dart
```

Expected: failure because state has no source-failure list or catalog sort and the page has no shared catalog toolbar.

- [ ] **Step 3: Implement independent loading, sorting, and card layout**

Refactor `_loadRemoteSource` and the `all` source path to emit per-source results, keep snapshots on failed refresh, and expose warning data. Add the toolbar sort control and warning beside refresh. Replace the horizontal listing tile layout with `TpCatalogCardShell` while preserving all MCP-specific actions.

- [ ] **Step 4: Run MCP tests and verify pass**

Run the same command. Expected: all MCP discovery tests pass.

- [ ] **Step 5: Commit MCP integration**

```bash
git add client/lib/cubits/mcp_discovery_cubit.dart client/lib/pages/mcp client/test/cubits/mcp_discovery_cubit_test.dart client/test/pages/mcp/mcp_discovery_section_test.dart
git commit -m "feat: make MCP discovery partial and sortable"
```

## Task 6: Migrate plugin discovery to adoption-first cards and warnings

**Files:**

- Modify: `client/lib/cubits/plugin_cubit.dart`
- Modify: `client/lib/pages/plugins/plugin_discovery_section.dart`
- Modify: `client/lib/pages/plugins/plugin_management_cards.dart`
- Modify: `client/test/cubits/plugin_cubit_test.dart`
- Modify: `client/test/pages/plugins/plugin_discovery_section_test.dart`

**Interfaces:**

- `PluginState` stores `CatalogSortKey discoverySort` and `List<CatalogSourceFailure> discoveryFailures`.
- Marketplace sync keeps successful discoverables and records failed marketplace labels/messages.
- `PluginCubit.setDiscoverySort(CatalogSortKey sort)` updates visible ordering without re-fetching.
- `PluginDiscoverableCard` uses the shared shell, metadata row, details button, and install/installed action.

- [ ] **Step 1: Write failing plugin tests**

Create discoverable plugin fixtures with adoption values and null metrics, add one successful and one failing marketplace fixture, and assert default adoption order, null-last behavior, warning tooltip, placeholder metrics, and install action.

- [ ] **Step 2: Run plugin tests and verify failure**

```bash
cd client
flutter test test/cubits/plugin_cubit_test.dart test/pages/plugins/plugin_discovery_section_test.dart
```

Expected: failure because the plugin state, toolbar, and card do not expose the catalog contract.

- [ ] **Step 3: Implement plugin state, toolbar, and card migration**

Use the shared comparator after marketplace aggregation, retain cached entries during sync, render warning beside refresh, and keep the existing marketplace/status filters and install behavior.

- [ ] **Step 4: Run plugin tests and verify pass**

Run the same command. Expected: all plugin discovery tests pass.

- [ ] **Step 5: Commit plugin integration**

```bash
git add client/lib/cubits/plugin_cubit.dart client/lib/pages/plugins client/test/cubits/plugin_cubit_test.dart client/test/pages/plugins/plugin_discovery_section_test.dart
git commit -m "feat: make plugin discovery partial and sortable"
```

## Task 7: Migrate Team Hub and Expert Hub to the shared catalog contract

**Files:**

- Modify: `client/lib/cubits/team_hub_cubit.dart`
- Modify: `client/lib/pages/team_hub/team_hub_body.dart`
- Modify: `client/lib/pages/team_hub/team_hub_cards.dart`
- Modify: `client/lib/services/team_hub/team_hub_source.dart`
- Modify: `client/lib/services/team_hub/git_registry_team_hub_source.dart`
- Modify: `client/lib/cubits/expert_hub_cubit.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_body.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_cards.dart`
- Modify: `client/lib/services/expert_hub/expert_hub_source.dart`
- Modify: `client/lib/services/expert_hub/git_registry_expert_hub_source.dart`
- Test: `client/test/cubits/team_hub_cubit_test.dart`
- Test: `client/test/cubits/expert_hub_cubit_test.dart`
- Test: `client/test/pages/team_hub/team_hub_body_test.dart`
- Test: `client/test/pages/expert_hub/expert_hub_body_test.dart`

**Interfaces:**

- Replace `TeamSort` and `MemberSort` with `CatalogSortKey` in state and page controls.
- `TeamHubSource.sourceId`/`sourceLabel` and `ExpertHubSource.sourceId`/`sourceLabel` identify the registry for warning records.
- Registry sources distinguish `null` network/error results from a valid empty list and retain the last cache when force refresh fails.
- `visibleTeams` and `visibleMembers` apply category/favorite/source/search filters first, then the shared comparator.
- Team and expert cards use the shared shell while preserving favorites, clone/add, source badges, dependency summaries, and locale overlays.

- [ ] **Step 1: Write failing team/expert tests**

Assert each hub defaults to adoption sorting, supports all five keys, places null metrics last, keeps cached entries after a failed force refresh, shows the warning beside refresh, renders all metric placeholders, and preserves clone/add actions.

- [ ] **Step 2: Run team/expert tests and verify failure**

```bash
cd client
flutter test test/cubits/team_hub_cubit_test.dart test/cubits/expert_hub_cubit_test.dart test/pages/team_hub/team_hub_body_test.dart test/pages/expert_hub/expert_hub_body_test.dart
```

Expected: failure because the current hubs support only name/updated sorting and collapse source failure into a page error.

- [ ] **Step 3: Implement hub model/source/state/card migration**

Add source identity and failure retention, replace local sorting switches with `CatalogSortComparator`, add the five-option toolbar, and compose shared cards without moving domain-specific clone/add/favorite logic into shared_ui.

- [ ] **Step 4: Run team/expert tests and verify pass**

Run the same command. Expected: all team and expert tests pass.

- [ ] **Step 5: Commit hub integration**

```bash
git add client/lib/cubits/team_hub_cubit.dart client/lib/pages/team_hub client/lib/services/team_hub client/lib/cubits/expert_hub_cubit.dart client/lib/pages/expert_hub client/lib/services/expert_hub client/test/cubits/team_hub_cubit_test.dart client/test/cubits/expert_hub_cubit_test.dart client/test/pages/team_hub/team_hub_body_test.dart client/test/pages/expert_hub/expert_hub_body_test.dart
git commit -m "feat: add catalog ranking to team and expert hubs"
```

## Task 8: Complete localization, manifest fixtures, and cross-catalog verification

**Files:**

- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Modify: generated `client/lib/l10n/app_localizations_en.dart`
- Modify: generated `client/lib/l10n/app_localizations_zh.dart`
- Modify: `team-hub/teams/gstack-req-dev/team.json`
- Modify: `member-hub/members/gstack-developer/member.json`
- Modify: affected fixtures under `client/test/fixtures/` and domain test helpers.
- Test: `client/test/pages/skills/skill_discovery_section_test.dart`
- Test: `client/test/pages/mcp/mcp_discovery_section_test.dart`
- Test: `client/test/pages/plugins/plugin_discovery_section_test.dart`
- Test: `client/test/pages/team_hub/team_hub_body_test.dart`
- Test: `client/test/pages/expert_hub/expert_hub_body_test.dart`

**Interfaces:**

- Every catalog uses the same localized sort labels and warning semantics.
- Every catalog fixture can omit metrics and still renders a stable four-slot card.
- Every catalog fixture can include the complete metrics object and sorts by adoption.

- [ ] **Step 1: Add cross-catalog fixture assertions**

Add one shared fixture per resource kind with complete metrics and one with omitted metrics. Assert the default sort, card metadata slots, missing-value `—`, and domain action in all five pages.

- [ ] **Step 2: Run the cross-catalog widget tests and verify failure where coverage is absent**

```bash
cd client
flutter test test/pages/skills/skill_discovery_section_test.dart test/pages/mcp/mcp_discovery_section_test.dart test/pages/plugins/plugin_discovery_section_test.dart test/pages/team_hub/team_hub_body_test.dart test/pages/expert_hub/expert_hub_body_test.dart
```

Expected: any remaining old sort/error assertions fail and identify the final integration gaps.

- [ ] **Step 3: Update fixtures and generated localization output**

Regenerate localization, update only the catalog manifest fixtures, and replace old page-specific sort/error text assertions with the shared behavior.

- [ ] **Step 4: Run the complete required verification**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```

Expected: analyzer exits 0 and the non-integration test suite reports 0 failures.

- [ ] **Step 5: Inspect the final diff and commit integration**

```bash
git diff --check
git status --short
git diff --stat HEAD~1
git add client/lib client/test client/packages/shared_ui team-hub member-hub
git commit -m "feat: unify catalog ranking and install cards"
```

The final staging command must include only files belonging to this feature; do not stage the pre-existing modified files listed by `git status` before implementation began.

## Self-review checklist

- [ ] Every acceptance criterion in the approved design maps to at least one task and test.
- [ ] No task relies on a page-specific comparator or timestamp unit.
- [ ] Shared UI has no imports from `teampilot` cubits/models.
- [ ] Partial failures preserve successful entries and expose sanitized source diagnostics.
- [ ] All five primary actions remain domain-owned.
- [ ] No statistics are fabricated when source data is absent.
- [ ] The final full analyze/test command is run before claiming completion.
