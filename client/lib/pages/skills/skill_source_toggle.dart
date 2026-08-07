import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';


class SkillSourceToggle extends StatelessWidget {
  const SkillSourceToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TpHover(
      backgroundColor: selected ? cs.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primaryContainer : cs.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: selected
              ? TpTextStyles.of(context).mdBold
              : TpTextStyles.of(context).mdSemibold,
        ),
      ),
    );
  }
}
