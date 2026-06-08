import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/extension_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_extensions_section.dart';

class ProjectExtensionsSection extends StatefulWidget {
  const ProjectExtensionsSection({required this.projectId, super.key});

  final String projectId;

  @override
  State<ProjectExtensionsSection> createState() =>
      _ProjectExtensionsSectionState();
}

class _ProjectExtensionsSectionState extends State<ProjectExtensionsSection> {
  Map<String, bool> _overrides = const {};

  @override
  void initState() {
    super.initState();
    _loadOverrides();
  }

  @override
  void didUpdateWidget(covariant ProjectExtensionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _loadOverrides();
  }

  Future<void> _loadOverrides() async {
    final map = await context.read<ExtensionCubit>().projectOverrides(
      widget.projectId,
    );
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
    await context.read<ExtensionCubit>().setProjectOverride(
      widget.projectId,
      id,
      value,
    );
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
                TeamConfigCardHeader(title: l10n.projectExtensionsTitle),
                const SizedBox(height: 6),
                Text(
                  l10n.projectExtensionsSubtitle,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 14),
                for (final row in rows)
                  TeamExtensionRow(
                    row: row,
                    choice: _choiceFor(row.id),
                    effective: _effective(row),
                    onChoice: (c) => _setChoice(row.id, c),
                    effectiveOnLabel: l10n.projectExtensionEffectiveOn,
                    effectiveOffLabel: l10n.projectExtensionEffectiveOff,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
