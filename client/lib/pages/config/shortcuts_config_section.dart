import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:teampilot/theme/app_text_styles.dart';

import '../../cubits/shortcut_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/command_catalog.dart';
import '../../services/commands/command_definition.dart';
import '../../services/commands/command_l10n.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/key_chord_formatter.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import '../../widgets/settings/workspace_hub_shell.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../../widgets/shortcuts/shortcut_cheatsheet_dialog.dart';
import '../../widgets/shortcuts/shortcut_rebind_dialog.dart';
import 'shortcuts_footer_actions.dart';

/// Settings section: search + grouped list of every catalog command's
/// current binding, plus reset-all / export / import (see
/// `shortcuts_footer_actions.dart`).
///
/// See docs/superpowers/specs/2026-07-11-keyboard-shortcuts-platform-design.md
/// ("Settings UX").
class ShortcutsConfigWorkspace extends StatefulWidget {
  const ShortcutsConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  State<ShortcutsConfigWorkspace> createState() =>
      _ShortcutsConfigWorkspaceState();
}

class _ShortcutsConfigWorkspaceState extends State<ShortcutsConfigWorkspace> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          WorkspaceSectionHeading(
            title: l10n.shortcutsSettingsTitle,
            subtitle: l10n.shortcutsPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.shortcutsSearchHint,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => showShortcutCheatsheetDialog(context),
              icon: const Icon(Icons.keyboard_outlined),
              label: Text(l10n.shortcutsCheatsheetButton),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: BlocBuilder<ShortcutCubit, ShortcutState>(
            builder: (context, state) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SettingsSurfaceCard(
                      child: _ShortcutGroupList(state: state, query: _query),
                    ),
                    const SizedBox(height: 12),
                    SettingsSurfaceCard(
                      child: ShortcutsFooterActions(state: state),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

bool _matchesQuery(
  AppLocalizations l10n,
  CommandDefinition def,
  List<KeyChord> chords,
  String query,
) {
  if (query.isEmpty) return true;
  final needle = query.trim().toLowerCase();
  if (def.id.toLowerCase().contains(needle)) return true;
  if (titleForCommand(l10n, def.id).toLowerCase().contains(needle)) {
    return true;
  }
  final isMacOS = defaultIsMacOS();
  return chords.any(
    (chord) =>
        formatKeyChord(chord, isMacOS: isMacOS).toLowerCase().contains(needle),
  );
}

class _ShortcutGroupList extends StatelessWidget {
  const _ShortcutGroupList({required this.state, required this.query});

  final ShortcutState state;
  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final effective = state.effective;
    final conflictedIds = {
      for (final conflict in state.conflicts) ...conflict.commandIds,
    };

    final sections = <Widget>[];
    for (final category in CommandCategory.values) {
      final defs = CommandCatalog.v1
          .where(
            (def) =>
                def.category == category &&
                _matchesQuery(l10n, def, effective[def.id] ?? const [], query),
          )
          .toList(growable: false);
      if (defs.isEmpty) continue;

      sections.add(
        SettingsGroupHeader(title: titleForCategory(l10n, category)),
      );
      for (final (index, def) in defs.indexed) {
        sections.add(
          _ShortcutRow(
            def: def,
            chords: effective[def.id] ?? const [],
            conflicted: conflictedIds.contains(def.id),
            showDividerBelow: index < defs.length - 1,
          ),
        );
      }
    }

    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l10n.shortcutsCheatsheetEmpty,
          style: AppTextStyles.of(context).mutedMd,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.def,
    required this.chords,
    required this.conflicted,
    required this.showDividerBelow,
  });

  final CommandDefinition def;
  final List<KeyChord> chords;
  final bool conflicted;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOS = defaultIsMacOS();
    final cs = Theme.of(context).colorScheme;

    return SettingsLabeledRow(
      title: titleForCommand(l10n, def.id),
      titleLeading: conflicted
          ? Tooltip(
              message: l10n.shortcutsConflictBadgeTooltip,
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: cs.error,
              ),
            )
          : null,
      showDividerBelow: showDividerBelow,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chords.isEmpty)
            Text(
              l10n.shortcutsNotSet,
              style: AppTextStyles.of(context).mutedSm,
            )
          else
            Wrap(
              spacing: 6,
              alignment: WrapAlignment.end,
              children: [
                for (final chord in chords)
                  _ChordChip(label: formatKeyChord(chord, isMacOS: isMacOS)),
              ],
            ),
          const SizedBox(width: 8),
          SidebarActionMenuButton(
            size: AppIconButton.kCompactSize,
            icon: Icon(
              Icons.more_vert,
              size: context.appIconSizes.sm,
              color: cs.onSurfaceVariant,
            ),
            specs: [
              SidebarActionMenuSpec.item(
                value: _ShortcutRowAction.change,
                icon: Icons.edit_outlined,
                label: l10n.shortcutsChangeAction,
              ),
              SidebarActionMenuSpec.item(
                value: _ShortcutRowAction.reset,
                icon: Icons.restart_alt_outlined,
                label: l10n.shortcutsResetAction,
              ),
              SidebarActionMenuSpec.item(
                value: _ShortcutRowAction.unbind,
                icon: Icons.link_off_outlined,
                label: l10n.shortcutsUnbindAction,
              ),
            ],
            onSelected: (action) {
              if (action is! _ShortcutRowAction) return;
              unawaited(_onAction(context, action));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _onAction(BuildContext context, _ShortcutRowAction action) {
    final cubit = context.read<ShortcutCubit>();
    return switch (action) {
      _ShortcutRowAction.change => showShortcutRebindDialog(
        context,
        commandId: def.id,
      ),
      _ShortcutRowAction.reset => cubit.resetCommand(def.id),
      _ShortcutRowAction.unbind => cubit.unbind(def.id),
    };
  }
}

enum _ShortcutRowAction { change, reset, unbind }

class _ChordChip extends StatelessWidget {
  const _ChordChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.workspaceSubtleSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: AppTextStyles.of(context).sm),
    );
  }
}
