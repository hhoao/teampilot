# Catalog Card Compact Metrics

## Goal

Make public catalog cards read like common marketplace cards: a single bottom metrics line with icon + value for adoption and rating, instead of four labeled metric tiles.

## Scope

- Change shared `TpCatalogMetadataRow` to two slots only: adoption and rating.
- Render each slot as a single-line `icon + value` (no visible label text).
- Keep missing values as `—` with the existing missing-data tooltip.
- Update all five catalog card call sites that pass four metrics:
  - Skills Discovery (`marketplace_skill_card.dart`)
  - Plugin Discovery (`plugin_discovery_section.dart`)
  - MCP Discovery (`mcp_shared_widgets.dart`)
  - Team Hub (`team_hub_cards.dart`)
  - Expert Hub (`expert_hub_cards.dart`)
- Update shared_ui and app tests that assert the four-slot / labeled layout.

## Non-goals

- No detail-page date fields in this change.
- No merge of metrics and action button into one footer row.
- No card height / grid cell re-layout beyond what the shorter metadata row naturally frees.
- No sort-key or `CatalogMetrics` model changes; updated/published remain available for sorting and future detail UI.
- No deletion of unused `catalogMetricUpdated` / `catalogMetricPublished` l10n keys in this change.

## Product behavior

Card footer metadata becomes:

```text
Name                                      source / author
Description
[domain-specific body]

⬇ 128    ★ 4.5
                                      [resource action]
```

Rules:

1. Only adoption and rating appear on the card.
2. Each metric is `icon + value` on one horizontal line; label text is not shown.
3. When a value is missing, show `—` and tooltip with the existing missing-data string (`catalogMetricMissingTooltip` / equivalent).
4. `TpCatalogMetricView.label` remains on the model for accessibility / tooltip context if useful, but must not render as a second text line.
5. Metrics stay above the action button; `TpCatalogCardShell` footer structure is unchanged.
6. Updated and published dates are omitted from cards; they remain in data and sort menus.

## Architecture

### Shared UI

`client/packages/shared_ui/lib/src/components/catalog/tp_catalog_metadata_row.dart`:

- Constructor accepts only `adoption` and `rating`.
- Replace the labeled two-line `_TpCatalogMetricTile` with a compact chip/row: small icon + value text.
- Drop the large `minWidth: 88` / `maxWidth: 180` tile constraints that forced marketplace-unlike wrapping.
- Prefer a single non-wrapping `Row` with modest spacing between the two metrics; allow ellipsis on overflow rather than wrapping into a second metadata line.

`TpCatalogCardShell` keeps taking an opaque `metadata` widget; no shell API change required.

### App call sites

Each of the five cards stops constructing `updated` / `published` `TpCatalogMetricView`s for the metadata row. Date helper usage used only for those slots can be removed from the card widgets if it becomes unused.

### Tests

- `tp_catalog_metadata_row_test.dart`: assert two icons/values, missing `—`, and absence of visible label strings such as “Installs” / “Rating” when those are only model labels.
- Hub / catalog UI tests that expect `TpCatalogMetadataRow` remain valid; any assertions on updated/published card text must be removed or moved if present.

## Migration / compatibility

This is a breaking API change for `TpCatalogMetadataRow` inside the monorepo. All in-repo call sites are updated in the same change. No persisted user data or remote catalog schemas change.

## Success criteria

- Public catalog cards show a compact bottom metrics line with adoption and rating only.
- Missing metrics still show `—` with a tooltip.
- Sort by updated/published still works from toolbar controls.
- Shared and affected app widget tests pass.
