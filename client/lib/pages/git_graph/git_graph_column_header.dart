import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import 'git_graph_columns.dart';

class GitGraphColumnHeader extends StatelessWidget {
  const GitGraphColumnHeader({
    super.key,
    required this.graphWidth,
    required this.onHide,
  });

  final double graphWidth;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = TpTextStyles.of(
      context,
    ).xsColored(colorScheme.onSurfaceVariant);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (details) => _showMenu(
        context,
        details.globalPosition,
        l10n.gitGraphHideColumnHeader,
      ),
      child: Container(
        height: GitGraphColumns.headerHeight,
        padding: const EdgeInsets.only(right: GitGraphColumns.trailingPadding),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: graphWidth,
              child: _HeaderLabel(l10n.gitGraphColumnGraph, style: textStyle),
            ),
            const SizedBox(width: GitGraphColumns.afterGraphGap),
            Expanded(
              flex: GitGraphColumns.descriptionFlex,
              child: _HeaderLabel(
                l10n.gitGraphColumnDescription,
                style: textStyle,
              ),
            ),
            const SizedBox(width: GitGraphColumns.metaGap),
            Flexible(
              flex: GitGraphColumns.dateFlex,
              fit: FlexFit.loose,
              child: SizedBox(
                width: double.infinity,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _HeaderLabel(
                    l10n.gitGraphColumnDate,
                    style: textStyle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: GitGraphColumns.metaGap),
            Flexible(
              flex: GitGraphColumns.authorFlex,
              fit: FlexFit.loose,
              child: SizedBox(
                width: double.infinity,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _HeaderLabel(
                    l10n.gitGraphColumnAuthor,
                    style: textStyle,
                  ),
                ),
              ),
            ),
            const SizedBox(width: GitGraphColumns.metaGap),
            SizedBox(
              width: GitGraphColumns.commitWidth,
              child: _HeaderLabel(l10n.gitGraphColumnCommit, style: textStyle),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMenu(
    BuildContext context,
    Offset position,
    String hideLabel,
  ) async {
    final choice = await showTpActionMenuFromSpecs<String>(
      context: context,
      globalPosition: position,
      specs: [
        TpActionMenuSpec.item(
          value: 'hide',
          icon: Icons.visibility_off_outlined,
          label: hideLabel,
        ),
      ],
    );
    if (choice == 'hide') onHide();
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel(this.label, {required this.style});

  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    softWrap: false,
    style: style,
  );
}
