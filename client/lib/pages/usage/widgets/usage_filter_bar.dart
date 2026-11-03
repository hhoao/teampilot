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
        if (state.cli == CliTool.cursor && state.cursorAccounts.isNotEmpty) ...[
          Container(width: 1, height: 20, color: cs.outlineVariant),
          _CursorAccountFilter(state: state, cubit: cubit),
        ],
      ],
    );
  }
}

/// Account picker that appears next to the CLI filter when Cursor is selected.
/// "All accounts" is the default and yields the combined numbers.
class _CursorAccountFilter extends StatelessWidget {
  const _CursorAccountFilter({required this.state, required this.cubit});

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = state.cursorAccountId;
    return Container(
      height: usageFilterControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          icon: const Icon(Icons.expand_more, size: 18),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                context.l10n.sessionUsageAccountAll,
                style: TpTextStyles.of(context).xs,
              ),
            ),
            for (final account in state.cursorAccounts)
              DropdownMenuItem<String?>(
                value: account.accountId,
                child: Text(account.label, style: TpTextStyles.of(context).xs),
              ),
          ],
          onChanged: cubit.setCursorAccount,
        ),
      ),
    );
  }
}

class _CliFilter extends StatelessWidget {
  const _CliFilter({required this.state, required this.cubit});

  final SessionUsageState state;
  final SessionUsageCubit cubit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: usageFilterControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
                  size: context.tpIconSizes.md,
                  borderRadius: 4,
                  showBorder: false,
                ),
              ),
            ),
        ],
      ),
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
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 32,
          child: label == null
              ? SizedBox(width: 32, child: Center(child: icon))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(child: Text(label!, style: styles.md)),
                ),
        ),
      ),
    );
  }
}
