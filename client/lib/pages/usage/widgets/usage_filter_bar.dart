import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/session_usage_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/team_config.dart';
import '../../../widgets/cli/cli_brand_icon.dart';
import '../usage_format.dart';
import 'usage_date_range_picker.dart';

class UsageFilterBar extends StatelessWidget {
  const UsageFilterBar({required this.state, required this.cubit, super.key});

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        UsageDateRangePicker(state: state, cubit: cubit),
        Container(width: 1, height: 20, color: cs.outlineVariant),
        _CliFilter(state: state, cubit: cubit),
      ],
    );
  }
}

class _CliFilter extends StatelessWidget {
  const _CliFilter({required this.state, required this.cubit});

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _CliButton(
          label: context.l10n.sessionUsageCliAll,
          selected: state.cli == null,
          onTap: () => cubit.setCli(null),
        ),
        for (final cli in CliTool.values)
          Tooltip(
            message: usageCliLabel(cli),
            waitDuration: const Duration(milliseconds: 500),
            child: _CliButton(
              selected: state.cli == cli,
              onTap: () => cubit.setCli(cli),
              icon: CliBrandIcon(
                cli: cli,
                size: 18,
                borderRadius: 4,
                showBorder: false,
              ),
            ),
          ),
      ],
    );
  }
}

class _CliButton extends StatelessWidget {
  const _CliButton({
    required this.selected,
    required this.onTap,
    this.label,
    this.icon,
  });

  final bool selected;
  final VoidCallback onTap;
  final String? label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Material(
      color: selected ? cs.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: label == null
                ? icon
                : Text(
                    label!,
                    style: styles.xs.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
