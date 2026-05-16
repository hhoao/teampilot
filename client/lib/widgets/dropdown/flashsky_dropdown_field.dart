import 'package:flutter/material.dart';

import 'custom_dropdown.dart';
import 'flashskyai_dropdown_decoration.dart';

/// Default paddings and overlay height for [FlashskyDropdownField] (all surfaces share these).
const EdgeInsets kFlashskyDropdownClosedHeaderPadding = EdgeInsets.symmetric(
  vertical: 6,
  horizontal: 12,
);
const EdgeInsets kFlashskyDropdownExpandedHeaderPadding = EdgeInsets.symmetric(
  vertical: 6,
  horizontal: 12,
);
const EdgeInsets kFlashskyDropdownListItemPadding = EdgeInsets.symmetric(
  vertical: 6,
  horizontal: 12,
);
const double kFlashskyDropdownDefaultOverlayHeight = 260;

/// Flashsky-themed wrapper around [DropdownFlutter] with shared text builders and
/// unified spacing.
class FlashskyDropdownField<T extends Object> extends StatelessWidget {
  const FlashskyDropdownField({
    super.key,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.initialItem,
    this.hintText,
    this.decoration,
    this.overlayHeight,
    this.headerMaxLines = 1,
    this.listItemMaxLines = 1,
    this.enabled = true,
    this.disabledDecoration,
    this.closedHeaderPadding,
    this.expandedHeaderPadding,
    this.listItemPadding,
    this.listItemKey,
  });

  final List<T> items;
  final T? initialItem;
  final String? hintText;
  final String Function(T item) itemLabel;
  final ValueChanged<T?> onChanged;
  final CustomDropdownDecoration? decoration;
  final double? overlayHeight;
  final int headerMaxLines;
  final int listItemMaxLines;
  final bool enabled;
  final CustomDropdownDisabledDecoration? disabledDecoration;
  final EdgeInsets? closedHeaderPadding;
  final EdgeInsets? expandedHeaderPadding;
  final EdgeInsets? listItemPadding;
  final Key? Function(T item)? listItemKey;

  @override
  Widget build(BuildContext context) {
    final deco = decoration ?? FlashskyDropdownDecorations.denseField(context);
    final effectiveOverlay =
        overlayHeight ?? kFlashskyDropdownDefaultOverlayHeight;

    return DropdownFlutter<T>(
      items: items,
      initialItem: initialItem,
      hintText: hintText,
      excludeSelected: false,
      enabled: enabled,
      disabledDecoration: disabledDecoration,
      decoration: deco,
      closedHeaderPadding:
          closedHeaderPadding ?? kFlashskyDropdownClosedHeaderPadding,
      expandedHeaderPadding:
          expandedHeaderPadding ?? kFlashskyDropdownExpandedHeaderPadding,
      listItemPadding: listItemPadding ?? kFlashskyDropdownListItemPadding,
      overlayHeight: effectiveOverlay,
      onChanged: onChanged,
      headerBuilder: (context, item, _) => Text(
        itemLabel(item),
        maxLines: headerMaxLines,
        overflow: TextOverflow.ellipsis,
        style: deco.headerStyle,
      ),
      listItemBuilder: (context, item, _, __) {
        final k = listItemKey?.call(item);
        return Row(
          children: [
            Expanded(
              child: Text(
                itemLabel(item),
                key: k,
                maxLines: listItemMaxLines,
                overflow: TextOverflow.ellipsis,
                style: deco.listItemStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}
