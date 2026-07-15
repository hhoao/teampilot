import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/shortcut_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/command_catalog.dart';
import '../../services/commands/command_definition.dart';
import '../../services/commands/command_l10n.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/key_chord_formatter.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import 'package:shared_ui/shared_ui.dart';

/// Opens the read-only keyboard shortcuts cheatsheet (`Mod+/` and the
/// settings page button both land here).
Future<void> showShortcutCheatsheetDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const ShortcutCheatsheetDialog(),
  );
}

/// Read-only, grouped list of every catalog command's effective chords.
class ShortcutCheatsheetDialog extends StatelessWidget {
  const ShortcutCheatsheetDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return TpDialog(
      maxWidth: 560,
      maxHeight: 720,
      child: BlocBuilder<ShortcutCubit, ShortcutState>(
        builder: (context, state) {
          final effective = state.effective;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpDialogHeader(title: l10n.shortcutsCheatsheetTitle),
              Expanded(
                child: ListView(
                  children: [
                    for (final category in CommandCategory.values)
                      _CheatsheetCategorySection(
                        category: category,
                        effective: effective,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CheatsheetCategorySection extends StatelessWidget {
  const _CheatsheetCategorySection({
    required this.category,
    required this.effective,
  });

  final CommandCategory category;
  final Map<String, List<KeyChord>> effective;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final defs = CommandCatalog.v1
        .where((def) => def.category == category)
        .toList(growable: false);
    if (defs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(
              titleForCategory(l10n, category),
              style: AppTextStyles.of(context).xsTrackColored(
                Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final def in defs)
            _CheatsheetRow(
              title: titleForCommand(l10n, def.id),
              chords: effective[def.id] ?? const [],
            ),
        ],
      ),
    );
  }
}

class _CheatsheetRow extends StatelessWidget {
  const _CheatsheetRow({required this.title, required this.chords});

  final String title;
  final List<KeyChord> chords;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOS = defaultIsMacOS();
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 12),
          if (chords.isEmpty)
            Text(
              l10n.shortcutsNotSet,
              style: AppTextStyles.of(context).mutedSm,
            )
          else
            Wrap(
              spacing: 6,
              children: [
                for (final chord in chords)
                  _ChordChip(label: formatKeyChord(chord, isMacOS: isMacOS)),
              ],
            ),
        ],
      ),
    );
  }
}

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
      child: Text(
        label,
        style: AppTextStyles.of(context).smSemiboldColored(cs.onSurface),
      ),
    );
  }
}
