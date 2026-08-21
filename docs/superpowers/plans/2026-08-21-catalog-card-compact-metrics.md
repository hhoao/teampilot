# Catalog Card Compact Metrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four labeled catalog metric tiles with a single bottom row of icon + value for adoption and rating only.

**Architecture:** Change the shared `TpCatalogMetadataRow` API and rendering in `shared_ui`, then update the five catalog card call sites so they stop passing updated/published slots. Sorting and `CatalogMetrics` stay unchanged.

**Tech Stack:** Dart, Flutter, `shared_ui` (`TpCatalogMetadataRow`, `TpCatalogMetricView`, `TpTheme`), Flutter widget tests.

## Global Constraints

- Cards show only adoption and rating as `icon + value` on one horizontal line; no visible label text.
- Missing values render as `—` with the existing missing-data tooltip.
- Do not add detail-page dates, merge metrics with the action button, change sort keys, or delete unused l10n keys.
- `TpCatalogCardShell` footer structure stays: metadata above action.
- Follow red-green-refactor per task.
- Preserve unrelated dirty worktree changes; stage only files belonging to this feature.
- `client/packages/shared_ui` is a git submodule: commit shared_ui changes inside that repo first, then bump the parent pointer if needed.

---

## File Map

### Modify

- `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_metadata_row.dart` — two-slot compact row.
- `client/packages/shared_ui/test/components/catalog/tp_catalog_metadata_row_test.dart` — compact rendering assertions.
- `client/lib/pages/skills/marketplace_skill_card.dart` — drop updated/published; remove unused `_formatDate` if orphaned.
- `client/lib/pages/plugins/plugin_discovery_section.dart` — drop updated/published; drop unused `MaterialLocalizations` if orphaned.
- `client/lib/pages/mcp/mcp_shared_widgets.dart` — drop updated/published; remove `_formatCatalogDate` if only used by those slots.
- `client/lib/pages/team_hub/team_hub_cards.dart` — drop updated/published; remove `_date` / `_fallbackUpdatedAt` if orphaned.
- `client/lib/pages/expert_hub/expert_hub_cards.dart` — same as team hub card cleanup.

### Possibly touch (only if assertions break)

- `client/test/pages/team_hub/team_hub_catalog_ui_test.dart`
- `client/test/pages/expert_hub/expert_hub_catalog_ui_test.dart`
- `client/packages/shared_ui/test/components/catalog/tp_catalog_card_shell_test.dart` (if it constructs four-slot metadata)

---

### Task 1: Compact `TpCatalogMetadataRow` in shared_ui

**Files:**
- Modify: `client/packages/shared_ui/lib/src/components/catalog/tp_catalog_metadata_row.dart`
- Test: `client/packages/shared_ui/test/components/catalog/tp_catalog_metadata_row_test.dart`

**Interfaces:**
- Consumes: existing `TpCatalogMetricView(icon, label, value, missingValueTooltip)`
- Produces:

```dart
class TpCatalogMetadataRow extends StatelessWidget {
  const TpCatalogMetadataRow({
    super.key,
    required this.adoption,
    required this.rating,
  });

  final TpCatalogMetricView adoption;
  final TpCatalogMetricView rating;
}
```

- [ ] **Step 1: Rewrite the failing/updated test for compact two-slot layout**

Replace `client/packages/shared_ui/test/components/catalog/tp_catalog_metadata_row_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../support/tp_test_widgets.dart';

Widget _wrap(Widget child) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
  return MaterialApp(
    theme: ThemeData(colorScheme: scheme, useMaterial3: true),
    home: TpTheme(
      data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
      child: Scaffold(body: child),
    ),
  );
}

TpCatalogMetricView _metric(String label, String? value, IconData icon) {
  return TpCatalogMetricView(
    icon: icon,
    label: label,
    value: value,
    missingValueTooltip: 'No data for $label',
  );
}

void main() {
  testWidgets('renders compact adoption and rating without label text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        TpCatalogMetadataRow(
          adoption: _metric('Installs', '128', Icons.download),
          rating: _metric('Rating', null, Icons.star),
        ),
      ),
    );

    expect(find.text('128'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Installs'), findsNothing);
    expect(find.text('Rating'), findsNothing);
    expect(find.byIcon(Icons.download), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails for the old API/layout**

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/catalog/tp_catalog_metadata_row_test.dart
```

Expected: FAIL — either compile error (`updated`/`published` required) or `findsNothing` on `'Installs'` / `'Rating'` fails because labels still render.

- [ ] **Step 3: Implement compact two-slot row**

Replace `tp_catalog_metadata_row.dart` with:

```dart
import 'package:flutter/material.dart';

import '../../theme/tp_text_styles.dart';
import '../../theme/tp_theme.dart';

/// One localized metric displayed in a [TpCatalogMetadataRow].
@immutable
class TpCatalogMetricView {
  const TpCatalogMetricView({
    required this.icon,
    required this.label,
    required this.value,
    required this.missingValueTooltip,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String missingValueTooltip;
}

/// Compact adoption + rating footer shared by public catalog cards.
class TpCatalogMetadataRow extends StatelessWidget {
  const TpCatalogMetadataRow({
    super.key,
    required this.adoption,
    required this.rating,
  });

  final TpCatalogMetricView adoption;
  final TpCatalogMetricView rating;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    return Row(
      children: [
        Flexible(child: _TpCatalogMetricChip(metric: adoption)),
        SizedBox(width: spacing.md),
        Flexible(child: _TpCatalogMetricChip(metric: rating)),
      ],
    );
  }
}

class _TpCatalogMetricChip extends StatelessWidget {
  const _TpCatalogMetricChip({required this.metric});

  final TpCatalogMetricView metric;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;
    final scheme = Theme.of(context).colorScheme;
    final textStyles = TpTextStyles.of(context);
    final isMissing = metric.value == null;
    final value = metric.value ?? '—';
    final valueText = Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textStyles.smMediumColored(scheme.onSurface),
    );

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          metric.icon,
          size: context.tpIconSizes.sm,
          color: scheme.onSurface.withValues(alpha: 0.68),
        ),
        SizedBox(width: spacing.xs),
        Flexible(child: valueText),
      ],
    );

    if (!isMissing) return row;
    return Tooltip(message: metric.missingValueTooltip, child: row);
  }
}
```

- [ ] **Step 4: Run the metadata row test and pass**

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/catalog/tp_catalog_metadata_row_test.dart
```

Expected: PASS

- [ ] **Step 5: Fix `tp_catalog_card_shell_test` if it still passes four metrics**

Open `client/packages/shared_ui/test/components/catalog/tp_catalog_card_shell_test.dart`. If it constructs `TpCatalogMetadataRow` with `updated`/`published`, remove those named args so the package analyzes cleanly.

Run:

```bash
cd client/packages/shared_ui && flutter test test/components/catalog/
```

Expected: PASS

- [ ] **Step 6: Commit inside the shared_ui submodule**

```bash
cd client/packages/shared_ui
git add lib/src/components/catalog/tp_catalog_metadata_row.dart \
  test/components/catalog/tp_catalog_metadata_row_test.dart \
  test/components/catalog/tp_catalog_card_shell_test.dart
git commit -m "$(cat <<'EOF'
feat(catalog): compact adoption/rating metadata row

EOF
)"
cd ../../..
# parent repo: only stage the submodule pointer when Task 2 lands, or stage it with Task 2
```

---

### Task 2: Update five catalog card call sites

**Files:**
- Modify: `client/lib/pages/skills/marketplace_skill_card.dart`
- Modify: `client/lib/pages/plugins/plugin_discovery_section.dart`
- Modify: `client/lib/pages/mcp/mcp_shared_widgets.dart`
- Modify: `client/lib/pages/team_hub/team_hub_cards.dart`
- Modify: `client/lib/pages/expert_hub/expert_hub_cards.dart`
- Modify (only if needed): `client/test/pages/team_hub/team_hub_catalog_ui_test.dart`
- Modify (only if needed): `client/test/pages/expert_hub/expert_hub_catalog_ui_test.dart`
- Modify: parent `client/packages/shared_ui` submodule pointer

**Interfaces:**
- Consumes: `TpCatalogMetadataRow(adoption:, rating:)` from Task 1
- Produces: five cards that no longer pass `updated` / `published`

- [ ] **Step 1: Write a focused failing app test (or extend an existing one)**

In `client/test/pages/expert_hub/expert_hub_catalog_ui_test.dart`, after pumping a card with metrics, add assertions that dated label strings are absent from the card (if the card currently surfaces formatted dates). Prefer asserting via a pumped `ExpertHubCard` / `TpCatalogMetadataRow` that:

```dart
expect(find.textContaining('2026'), findsNothing); // or the fixture's formatted date
expect(find.byType(TpCatalogMetadataRow), findsOneWidget);
```

If existing fixtures have no dates, skip adding a new app test and rely on compile + shared_ui tests; still run the catalog UI tests in Step 4.

- [ ] **Step 2: Trim each `TpCatalogMetadataRow` to adoption + rating**

For every call site, delete the `updated:` and `published:` arguments. Example shape (skills):

```dart
metadata: TpCatalogMetadataRow(
  adoption: TpCatalogMetricView(
    icon: Icons.download_outlined,
    label: l10n.skillsCatalogAdoption,
    value: metrics.adoptionCount?.toString(),
    missingValueTooltip: l10n.catalogMetricMissingTooltip,
  ),
  rating: TpCatalogMetricView(
    icon: Icons.star_border,
    label: l10n.catalogMetricRating,
    value: metrics.rating?.toStringAsFixed(1),
    missingValueTooltip: l10n.catalogMetricMissingTooltip,
  ),
),
```

Apply the same deletion in:

- `marketplace_skill_card.dart`
- `plugin_discovery_section.dart` (`PluginDiscoverableCard` / discovery card builder)
- `mcp_shared_widgets.dart` (`McpCatalogListingTile`)
- `team_hub_cards.dart`
- `expert_hub_cards.dart`

- [ ] **Step 3: Remove orphaned date helpers**

After the deletions:

- `marketplace_skill_card.dart`: remove `static String? _formatDate(...)` if unused.
- `plugin_discovery_section.dart`: remove unused `final localizations = MaterialLocalizations.of(context);` if nothing else uses it.
- `mcp_shared_widgets.dart`: remove `_formatCatalogDate` if it is only used by the removed slots.
- `team_hub_cards.dart` / `expert_hub_cards.dart`: remove `_date` and `_fallbackUpdatedAt` if unused after the metadata trim.

Do not remove sort menu entries or l10n keys for updated/published.

- [ ] **Step 4: Run analyzer and focused tests**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/pages/skills/marketplace_skill_card.dart \
  lib/pages/plugins/plugin_discovery_section.dart \
  lib/pages/mcp/mcp_shared_widgets.dart \
  lib/pages/team_hub/team_hub_cards.dart \
  lib/pages/expert_hub/expert_hub_cards.dart

cd client && dart run tool/run_tests.dart \
  test/pages/team_hub/team_hub_catalog_ui_test.dart \
  test/pages/expert_hub/expert_hub_catalog_ui_test.dart

cd client/packages/shared_ui && flutter test test/components/catalog/
```

Expected: no errors; all listed tests PASS.

- [ ] **Step 5: Commit parent repo changes (and submodule pointer)**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/shared_ui \
  client/lib/pages/skills/marketplace_skill_card.dart \
  client/lib/pages/plugins/plugin_discovery_section.dart \
  client/lib/pages/mcp/mcp_shared_widgets.dart \
  client/lib/pages/team_hub/team_hub_cards.dart \
  client/lib/pages/expert_hub/expert_hub_cards.dart \
  client/test/pages/team_hub/team_hub_catalog_ui_test.dart \
  client/test/pages/expert_hub/expert_hub_catalog_ui_test.dart
git commit -m "$(cat <<'EOF'
feat(catalog): show compact adoption/rating on cards

EOF
)"
```

Only stage files that actually changed. Do not stage unrelated managed-provider or lockfile edits.

---

## Spec coverage checklist

| Spec requirement | Task |
| --- | --- |
| Two-slot API (adoption + rating only) | Task 1 |
| Icon + value, no label text | Task 1 |
| Missing `—` + tooltip | Task 1 |
| Five call sites updated | Task 2 |
| No detail dates / sort / l10n deletion | Global constraints |
| Tests updated | Task 1 + Task 2 |
| Shell footer unchanged | Global constraints (no shell edit) |

## Self-review notes

- No placeholders left in steps.
- API signature in Task 1 matches Task 2 call sites.
- Submodule commit order is explicit to avoid a broken parent pointer.
