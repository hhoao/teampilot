import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

class ManagedProviderEditorSectionShell extends StatelessWidget {
  static const EdgeInsets _tilePadding = EdgeInsets.fromLTRB(16, 12, 16, 12);
  static const EdgeInsets _childrenPadding = EdgeInsets.fromLTRB(16, 8, 16, 14);

  const ManagedProviderEditorSectionShell({
    required this.title,
    required this.initiallyExpanded,
    this.subtitle,
    required this.child,
    this.badge,
    this.referenceTip,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool initiallyExpanded;
  final Widget child;
  final String? badge;
  final String? referenceTip;

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

        // Keep collapsed sections mounted so their TpFormField registrations
        // survive; otherwise click-time form validation silently skips them.
        maintainState: true,
        tilePadding: _tilePadding,
        childrenPadding: _childrenPadding,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TpTextStyles.of(context).mdSemiboldTightSnug,
              ),
            ),
            if (referenceTip != null && referenceTip!.trim().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: TpInfoTipIcon(message: referenceTip!),
              ),
            ],
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
