# Unified Catalog Ranking and Install Cards

## Goal

Create one catalog experience for Skills, MCP servers, teams, experts, and plugins: each resource type has its own default popularity ranking, consistent install-oriented cards, shared metadata, and resilient partial-failure behavior.

The feature is intentionally a clean architectural migration. Existing catalog models and page-specific sorting APIs may be changed rather than preserved for backward compatibility.

## Scope

- Add independent ranking and sorting to the five discovery/catalog surfaces:
  - Skills Discovery
  - MCP Discovery
  - Plugin Discovery
  - Team Hub
  - Expert Hub
- Default each catalog to descending adoption/popularity.
- Support sorting by adoption count, rating, recently updated, publication date, and name.
- Standardize install-oriented card structure while retaining resource-specific actions and details.
- Show successful sources and entries when another source fails.
- Put source failures beside the refresh control as a warning icon with a hover tooltip containing the source name and error.
- Add a reusable catalog metadata contract so missing remote metrics can be filled by future APIs without another UI redesign.
- Extend catalog manifests and remote mapping to carry optional adoption, rating, rating count, updated, and published values.

## Non-goals

- No cross-resource leaderboard combining Skills, MCP, teams, experts, and plugins.
- No user rating submission or review workflow.
- No fake statistics. Missing metrics remain missing and are displayed as `—`.
- No ranking on installed-only lists or private My Teams / My Experts libraries; those surfaces may reuse the card metadata primitives but are not public catalogs.
- No replacement of domain-specific install, add, clone, dependency, or favorite behavior with one generic action implementation.

## Product behavior

Each catalog has its own sort state and data set. The default sort is `adoption` descending. Missing adoption values sort after entries with real values. Ties use `updated` descending and then `name` ascending so results are deterministic.

The sort menu contains:

1. Adoption / install count
2. Rating
3. Recently updated
4. Published date
5. Name

Sort labels use the resource's vocabulary. Skills, plugins, teams, and experts can display “installs” or “added”; MCP displays “uses”. The internal sort key remains `adoption` because it represents resource uptake without incorrectly calling MCP usage an installation.

Cards use a common layout:

```text
Name                                      source / author
Description

Adoption      Rating       Updated       Published

                                      [resource action]
```

All four metric slots remain structurally present. A missing value is rendered as `—` with an accessible tooltip such as “No data available”. Ratings are read-only and show the numeric rating plus rating count when available. The primary action is resource-specific:

- Skills: Install or Add repository
- MCP: Add
- Plugins: Install
- Teams: Clone
- Experts: Add

While a catalog refreshes, existing entries remain visible. A source failure does not replace the grid with an error page. The toolbar shows a warning icon immediately beside the refresh button; hovering it displays one line per failed source, including the source label and sanitized error message. If every source fails and there are no entries, the page shows the full empty/error state with retry.

## Architecture

### Catalog domain contract

Add a domain-independent catalog layer under `client/lib/services/catalog/` and `client/lib/models/catalog/`.

The core types are:

```dart
enum CatalogResourceKind { skill, mcp, plugin, team, expert }

enum CatalogSortKey { adoption, rating, updated, published, name }

class CatalogMetrics {
  const CatalogMetrics({
    this.adoptionCount,
    this.rating,
    this.ratingCount,
    this.updatedAtMs,
    this.publishedAtMs,
  });

  final int? adoptionCount;
  final double? rating;
  final int? ratingCount;
  final int? updatedAtMs;
  final int? publishedAtMs;
}

abstract interface class CatalogEntry {
  String get id;
  CatalogResourceKind get kind;
  String get name;
  String get description;
  String? get sourceLabel;
  String? get author;
  List<String> get tags;
  CatalogMetrics get metrics;
}
```

The exact file split may use immutable data classes instead of the sketch above, but the public contract must keep metrics optional and normalize all timestamps to epoch milliseconds. A `CatalogSortComparator` owns null ordering, descending numeric/date ordering, and stable name tie-breaking. Pages must not duplicate comparator logic.

### Adapters and actions

Each domain provides an adapter from its existing model or remote listing to `CatalogEntry` plus a domain card/action adapter. The shared catalog layer must not import SkillCubit, McpCubit, TeamHubCubit, ExpertHubCubit, or PluginCubit.

The UI receives an entry, a card body builder, and an action callback/state. This gives all cards the same shell and metadata row while allowing team dependency summaries, MCP verification badges, skill language badges, plugin capabilities, and expert source badges to remain domain-specific.

### Query and source results

Catalog loading uses a source-neutral result shape:

```dart
class CatalogQuery {
  const CatalogQuery({
    this.search = '',
    this.sort = CatalogSortKey.adoption,
    this.page = 1,
    this.pageSize = 20,
  });

  final String search;
  final CatalogSortKey sort;
  final int page;
  final int pageSize;
}

class CatalogSourceResult {
  const CatalogSourceResult({
    required this.sourceId,
    required this.entries,
    this.hasNext = false,
    this.error,
  });

  final String sourceId;
  final List<CatalogEntry> entries;
  final bool hasNext;
  final String? error;
}
```

Remote sources receive the requested sort when their API supports it. Local/static sources sort with the shared comparator. A source result is independently successful or failed; aggregation merges successful entries and preserves failed-source diagnostics.

## Data schema

Public catalog records gain optional fields with these normalized meanings:

```json
{
  "metrics": {
    "adoptionCount": 0,
    "rating": 0.0,
    "ratingCount": 0,
    "updatedAtMs": 0,
    "publishedAtMs": 0
  }
}
```

`metrics` is omitted or contains null fields when a source does not provide data. Existing source-specific values map as follows:

- Skills `installs` → `adoptionCount`; `stars` is not silently treated as a rating.
- MCP `useCount` → `adoptionCount`; official/Smithery rating fields map only when explicitly available.
- Team and expert clone/add counts → `adoptionCount` when the registry supplies them.
- Plugin install/add counts → `adoptionCount` when the marketplace supplies them.
- Existing `updatedAt` values are converted to milliseconds at the adapter boundary.
- `publishedAtMs` is populated only from explicit catalog metadata; it is not inferred from `updatedAt`.

The registry manifest writers, readers, and remote mappers must use the same optional `metrics` shape. Missing fields remain null through serialization and adaptation.

## UI structure

Create reusable shared-ui primitives for visual structure only:

- `TpCatalogCardShell`
- `TpCatalogMetadataRow`
- `TpCatalogSortSelect` or equivalent sort control styling
- `TpCatalogSourceWarning`

Resource-specific catalog pages remain in `client/lib/pages/<domain>/`. Product actions and domain content remain outside `shared_ui`. The toolbar layout must work in wide grids and narrow mobile widths by stacking search, sort, refresh, and warning controls without overflow.

Each page's state owns its selected sort and source failures. The common UI accepts an immutable list of failure records rather than reading cubits directly.

## Error handling and refresh

The current Skills behavior that sets one global `discoveryError` and hides all merged entries is replaced with partial-result aggregation. The same rule applies to MCP, plugins, teams, and experts:

1. Start refresh while retaining existing entries.
2. Request all enabled sources independently.
3. Catch each source failure and record `{sourceId, sourceLabel, message}`.
4. Merge and render successful entries.
5. Expose failures beside refresh through the warning icon.
6. Only enter full error state when there are no entries and every requested source failed.

Error messages shown in tooltips must not include secrets, authorization headers, or raw response bodies. Retry re-requests failed sources and may also refresh all sources when the user presses the main refresh button.

## Testing

Pure catalog tests cover:

- Numeric, rating, date, and name sorting.
- Missing values sorting last.
- Stable tie-breaking.
- Timestamp normalization.
- Resource-specific adoption labels.
- Adapter mapping for all five resources.

Widget tests cover:

- Default adoption sort is selected.
- Changing sort reorders cards.
- All metric slots render, including `—` placeholders.
- Resource-specific actions remain present.
- One failed source leaves successful entries visible.
- The warning icon appears only when failures exist.
- Tooltip contains each failed source and error.
- All-source failure with no entries shows the full retry state.
- Refresh preserves existing entries during loading.

Existing source and install tests must be updated to assert the new result aggregation instead of expecting a global error card whenever one source fails.

## Acceptance criteria

- Each of the five catalogs independently defaults to adoption/popularity descending.
- Each supports adoption, rating, updated, published, and name sorting with deterministic missing-value behavior.
- Cards share the same metadata layout and use resource-specific primary actions.
- A failed source never hides successful entries.
- Failed sources are discoverable from a warning icon beside refresh via hover tooltip.
- Missing metrics are visibly reserved as `—` without fabricated values.
- A future source/API can provide metrics through the catalog contract without changing card or sorting code.
- No catalog page has duplicated null ordering or timestamp conversion logic.
