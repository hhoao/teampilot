import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

class ManagedProviderEditorSectionShell extends StatelessWidget {
  const ManagedProviderEditorSectionShell({
    required this.title,
    required this.subtitle,
    required this.initiallyExpanded,
    required this.child,
    this.badge,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool initiallyExpanded;
  final Widget child;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        key: ValueKey<Object?>((title, initiallyExpanded, badge)),
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(title, style: TpTextStyles.of(context).mdSemibold),
            ),
            if (badge != null) _SectionBadge(label: badge!),
          ],
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TpTextStyles.of(
                  context,
                ).smColored(colorScheme.onSurfaceVariant),
              ),
        children: [child],
      ),
    );
  }
}

class _SectionBadge extends StatelessWidget {
  const _SectionBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TpTextStyles.of(
          context,
        ).xsColored(colorScheme.onSecondaryContainer),
      ),
    );
  }
}
