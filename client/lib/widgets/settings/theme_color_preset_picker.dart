import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_theme.dart';
import '../../theme/workspace_surface_layers.dart';

class ThemeColorPresetPicker extends StatelessWidget {
  const ThemeColorPresetPicker({
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Align(
      alignment: Alignment.centerRight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final id in kThemeColorPresetIds)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: RepaintBoundary(
                  child: ThemeColorPresetChip(
                    id: id,
                    label: l10n.themeColorPresetName(id),
                    selected: id == selected,
                    onTap: () => onSelect(id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ThemeColorPresetChip extends StatefulWidget {
  const ThemeColorPresetChip({
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<ThemeColorPresetChip> createState() => _ThemeColorPresetChipState();
}

class _ThemeColorPresetChipState extends State<ThemeColorPresetChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = themePresetSwatchPrimary(widget.id);
    final secondary = themePresetSwatchSecondary(widget.id);
    final borderColor = widget.selected
        ? cs.primary
        : _hovered
        ? cs.primary.withValues(alpha: 0.55)
        : cs.outlineVariant;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: cs.workspaceInset,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: borderColor,
              width: widget.selected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(widget.label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
