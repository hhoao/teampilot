import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_theme.dart';
import '../../theme/workspace_surface_layers.dart';

class ThemeColorPresetPicker extends StatelessWidget {
  const ThemeColorPresetPicker({
    required this.selected,
    required this.onSelect,
    this.mobileBreakpoint = kTpSegmentedPickerMobileBreakpoint,
    super.key,
  });

  final String selected;
  final ValueChanged<String> onSelect;
  final double mobileBreakpoint;

  bool _useSelect(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  Widget _swatchLabel(BuildContext context, String id) {
    final l10n = context.l10n;
    final primary = themePresetSwatchPrimary(id);
    final secondary = themePresetSwatchSecondary(id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: secondary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            l10n.themeColorPresetName(id),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_useSelect(context)) {
      return SizedBox(
        width: double.infinity,
        child: TpCompactSelect<String>(
          value: selected,
          entries: [
            for (final id in kThemeColorPresetIds)
              (id, l10n.themeColorPresetName(id)),
          ],
          itemBuilder: _swatchLabel,
          listItemBuilder: _swatchLabel,
          onChanged: (v) {
            if (v != null) onSelect(v);
          },
        ),
      );
    }

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
    return TpHover(
      onTap: widget.onTap,
      onHoverChanged: (hovered) => setState(() => _hovered = hovered),
      borderRadius: BorderRadius.circular(999),
      backgroundColor: cs.workspaceInset,
      hoverColor: cs.workspaceInset,
      border: Border.all(
        color: borderColor,
        width: widget.selected ? 2 : 1,
      ),
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
    );
  }
}
