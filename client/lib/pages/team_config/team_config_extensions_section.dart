import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/extension_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'team_config_cards.dart';

enum ExtensionOverrideChoice { followGlobal, forceOn, forceOff }

class TeamExtensionsSection extends StatefulWidget {
  const TeamExtensionsSection({super.key, required this.team});

  final TeamConfig team;

  @override
  State<TeamExtensionsSection> createState() => TeamExtensionsSectionState();
}

class TeamExtensionsSectionState extends State<TeamExtensionsSection> {
  Map<String, bool> _overrides = const {};

  @override
  void initState() {
    super.initState();
    context.read<ExtensionCubit>().load();
    _loadOverrides();
  }

  @override
  void didUpdateWidget(covariant TeamExtensionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.team.id != widget.team.id) _loadOverrides();
  }

  Future<void> _loadOverrides() async {
    final map = await context.read<ExtensionCubit>().teamOverrides(widget.team.id);
    if (!mounted) return;
    setState(() => _overrides = map);
  }

  ExtensionOverrideChoice _choiceFor(String id) {
    if (!_overrides.containsKey(id)) return ExtensionOverrideChoice.followGlobal;
    return _overrides[id]!
        ? ExtensionOverrideChoice.forceOn
        : ExtensionOverrideChoice.forceOff;
  }

  bool _effective(ExtensionRow row) {
    final override = _overrides[row.id];
    return override ?? row.globalEnabled;
  }

  Future<void> _setChoice(String id, ExtensionOverrideChoice choice) async {
    final value = switch (choice) {
      ExtensionOverrideChoice.followGlobal => null,
      ExtensionOverrideChoice.forceOn => true,
      ExtensionOverrideChoice.forceOff => false,
    };
    await context.read<ExtensionCubit>().setTeamOverride(widget.team.id, id, value);
    await _loadOverrides();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = context.watch<ExtensionCubit>().state.rows;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TeamConfigCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TeamConfigCardHeader(title: l10n.teamExtensionsTitle),
                const SizedBox(height: 6),
                Text(
                  l10n.teamExtensionsSubtitle,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 14),
                for (final row in rows)
                  TeamExtensionRow(
                    row: row,
                    choice: _choiceFor(row.id),
                    effective: _effective(row),
                    onChoice: (c) => _setChoice(row.id, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TeamExtensionRow extends StatelessWidget {
  const TeamExtensionRow({super.key, 
    required this.row,
    required this.choice,
    required this.effective,
    required this.onChoice,
  });

  final ExtensionRow row;
  final ExtensionOverrideChoice choice;
  final bool effective;
  final ValueChanged<ExtensionOverrideChoice> onChoice;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    style: AppTextStyles.of(context)
                        .body
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    effective
                        ? l10n.teamExtensionEffectiveOn
                        : l10n.teamExtensionEffectiveOff,
                    style: AppTextStyles.of(context).bodySmall.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                ],
              ),
            ),
            DropdownButton<ExtensionOverrideChoice>(
              value: choice,
              underline: const SizedBox.shrink(),
              onChanged: (c) {
                if (c != null) onChoice(c);
              },
              items: [
                DropdownMenuItem(
                  value: ExtensionOverrideChoice.followGlobal,
                  child: Text(l10n.teamExtensionFollowGlobal),
                ),
                DropdownMenuItem(
                  value: ExtensionOverrideChoice.forceOn,
                  child: Text(l10n.teamExtensionForceOn),
                ),
                DropdownMenuItem(
                  value: ExtensionOverrideChoice.forceOff,
                  child: Text(l10n.teamExtensionForceOff),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
