# Expert editor: compact deps via nested picker

Create/edit expert (`ExpertEditorDialog`) currently inlines every installed skill, plugin, and MCP as checkbox rows. With a large local catalog the dialog becomes very long and hard to scan.

## Goal

Keep persona fields (name, description, category, prompt, playbook, tags) on the main dialog. Move dependency selection into a nested configure dialog per category. Main dialog shows only a configure control and the selected count (including `0`).

Save semantics (`resolveExpertEditorDeps`, non-portable skip toast, orphan retention) stay unchanged.

## Non-goals

- Team config skills/plugins/MCP pages and their inline lists.
- Search / filter inside the picker (YAGNI this round).
- Changing capability-pack merge, portability rules, or `DiscoverableMember` schema.
- Chips or name lists of selected deps on the main dialog.

## Main dialog (dependency section)

Replace the three inline full lists with three rows: Skills, Plugins, MCP.

Each row:

| Element | Behavior |
|---------|----------|
| Title | Existing section label (`expertEditorSkillsSection` / plugins / mcp) |
| Count | Always show selected count as a number, including `0` |
| Configure | Opens the nested picker for that category only |

Count includes currently selected orphan deps (still checked but missing locally).

Persona fields and Cancel / Create|Save actions are unchanged. Submit still builds deps via `resolveExpertEditorDeps` from `_selectedSkillIds` / `_selectedPluginIds` / `_selectedMcpIds`.

## Nested picker dialog

Tapping Configure opens a second `AppDialog` for one category:

- **Title:** Configure Skills / Plugins / MCP (new l10n keys).
- **Sizing:** `scrollable: true` with `maxHeight` ≈ 85% of viewport (same pattern as today’s expert editor) so large catalogs scroll instead of clipping.
- **Body:** Same installed catalog as today (`SkillCubit` enabled / `PluginCubit` installed / `McpCubit` enabled), rendered with existing `TeamSkillRow` / `TeamPluginRow` / `TeamMcpRow`. Empty catalog → existing empty copy.
- **Orphans:** Selected deps missing from the catalog stay at the top with existing orphan remove UI.
- **Actions:** Cancel discards picker-local edits; Done commits the temporary selection set back to the parent dialog’s `_selected*Ids` and closes.

### Picker inputs

| Input | Purpose |
|-------|---------|
| Category | skills / plugins / mcp |
| Seed `selectedIds` | Copy of parent `_selected*Ids` for that category |
| Catalog list | Installed items (or test inject) |
| Existing dep refs | `_existing*Deps` — needed for orphan labels / remove targets, not only ids |

Only one picker is open at a time. Catalog lists are not rendered on the main dialog until a picker opens (optional inject lists for tests remain on `showExpertEditorDialog`).

## Components

| File | Role |
|------|------|
| `expert_editor_dialog.dart` | Main dialog: three compact dep rows; open pickers; submit unchanged |
| `expert_editor_dep_picker_dialog.dart` (new) | Nested picker for one category |
| Optional small row widget | Title + count + Configure button |
| `expert_editor_deps.dart` | Unchanged resolve helpers |

## l10n

Add keys for Configure, picker titles, and Done. Count is a bare number (no “configured” label). Reuse existing empty / orphan / section title strings where possible.

## Testing

Update `expert_editor_dialog_test.dart`:

1. Opening the main dialog does not put skill/plugin/mcp catalog rows on the tree.
2. Configure Skills → toggle portable skill → Done → main count shows `1` → submit persists `skillDeps`.
3. Picker Cancel leaves parent selection unchanged.
4. Edit mode with an orphan skill: main count includes it; remove orphan in picker → Done → count decreases.
5. Existing create/edit without deps still pass.

## Out of scope reminders

- No search in picker.
- No team-config UI changes.
- No change to `resolveExpertEditorDeps` behavior.
