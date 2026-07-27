import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/shortcut_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/command_l10n.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/key_chord_formatter.dart';
import '../../services/workbench/workbench_center_mode.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/team_pilot_brand_logo.dart';

/// Workbench empty-center welcome: brand mark + curated actionable shortcuts.
class WorkbenchWelcomePage extends StatelessWidget {
  const WorkbenchWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;

    return KeyedSubtree(
      key: AppKeys.workbenchWelcomePage,
      child: ColoredBox(
        color: cs.surface,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.xl,
              vertical: spacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TeamPilotBrandLogo(
                  size: 96,
                  color: cs.onSurface.withValues(alpha: 0.35),
                ),
                SizedBox(height: spacing.xxl),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: BlocBuilder<ShortcutCubit, ShortcutState>(
                    builder: (context, state) {
                      final effective = state.effective;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final id in kWorkbenchWelcomeCommandIds)
                            _WelcomeShortcutRow(
                              commandId: id,
                              chords: effective[id] ?? const [],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeShortcutRow extends StatelessWidget {
  const _WelcomeShortcutRow({required this.commandId, required this.chords});

  final String commandId;
  final List<KeyChord> chords;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOS = defaultIsMacOS();
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: AppKeys.workbenchWelcomeCommandRow(commandId),
        onTap: () => context.read<CommandBus>().invoke(commandId),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  titleForCommand(l10n, commandId),
                  style: TpTextStyles.of(context).mdColored(cs.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              if (chords.isEmpty)
                Text(
                  l10n.shortcutsNotSet,
                  style: TpTextStyles.of(context).mutedSm,
                )
              else
                Wrap(
                  spacing: 6,
                  children: [
                    for (final chord in chords)
                      _ChordChip(
                        label: formatKeyChord(chord, isMacOS: isMacOS),
                      ),
                  ],
                ),
            ],
          ),
        ),
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
        style: TpTextStyles.of(context).smSemiboldColored(cs.onSurface),
      ),
    );
  }
}
