import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import 'app_dropdown_decoration.dart';
import 'dropdown_menu_item_button.dart';
import 'popover/app_popover.dart';

/// Default paddings and overlay height for [AppDropdownField].
const EdgeInsets kAppDropdownClosedHeaderPadding = EdgeInsets.symmetric(
  vertical: 6,
  horizontal: 12,
);
const EdgeInsets kAppDropdownExpandedHeaderPadding = EdgeInsets.symmetric(
  vertical: 6,
  horizontal: 12,
);
const EdgeInsets kAppDropdownListItemPadding = EdgeInsets.symmetric(
  vertical: 6,
  horizontal: 12,
);
const double kAppDropdownDefaultOverlayHeight = 260;

/// Vertical gap between rows in dropdown / picker overlays.
const double kAppDropdownListItemGap = 4;

/// TeamPilot dropdown using AppFlowy's popover + list pattern.
class AppDropdownField<T extends Object> extends StatefulWidget {
  const AppDropdownField({
    super.key,
    required this.items,
    required this.onChanged,
    this.itemLabel,
    this.itemBuilder,
    this.listItemBuilder,
    this.initialItem,
    this.hintText,
    this.decoration,
    this.overlayHeight,
    this.headerMaxLines = 1,
    this.listItemMaxLines = 1,
    this.enabled = true,
    this.closedHeaderPadding,
    this.expandedHeaderPadding,
    this.listItemPadding,
    this.listItemKey,
    this.controller,
  }) : assert(
         itemLabel != null || itemBuilder != null || listItemBuilder != null,
         'Provide itemLabel, itemBuilder, or listItemBuilder',
       );

  final List<T> items;
  final T? initialItem;
  final String? hintText;
  final String Function(T item)? itemLabel;
  final Widget Function(BuildContext context, T item)? itemBuilder;
  final Widget Function(BuildContext context, T item)? listItemBuilder;
  final ValueChanged<T?> onChanged;
  final AppDropdownDecoration? decoration;
  final double? overlayHeight;
  final int headerMaxLines;
  final int listItemMaxLines;
  final bool enabled;
  final EdgeInsets? closedHeaderPadding;
  final EdgeInsets? expandedHeaderPadding;
  final EdgeInsets? listItemPadding;
  final Key? Function(T item)? listItemKey;
  final AppPopoverController? controller;

  @override
  State<AppDropdownField<T>> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T extends Object>
    extends State<AppDropdownField<T>> {
  final GlobalKey _triggerKey = GlobalKey();
  late final AppPopoverController _popoverController;
  late final bool _ownsController;
  late T? _selected;
  bool _isHovering = false;

  /// Measured trigger width for the overlay panel. Updated after layout only —
  /// never read [RenderBox] during [build] or constrain the trigger from it.
  double? _overlayWidth;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _popoverController = widget.controller ?? AppPopoverController();
    _popoverController.addListener(_onPopoverChanged);
    _selected = widget.initialItem;
  }

  @override
  void didUpdateWidget(AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialItem != oldWidget.initialItem) {
      _selected = widget.initialItem;
    }
  }

  @override
  void dispose() {
    _popoverController.removeListener(_onPopoverChanged);
    if (_ownsController) {
      _popoverController.dispose();
    }
    super.dispose();
  }

  void _onPopoverChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_popoverController.isOpen) {
        _syncOverlayWidth();
        return;
      }
      if (_overlayWidth != null) {
        setState(() => _overlayWidth = null);
      }
    });
  }

  void _syncOverlayWidth() {
    if (!mounted || !_popoverController.isOpen) return;
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlayWidth());
      return;
    }
    final width = box.size.width;
    if (_overlayWidth == width) return;
    setState(() => _overlayWidth = width);
  }

  void _toggleMenu() {
    if (!widget.enabled) return;
    if (_popoverController.isOpen) {
      _popoverController.hide();
    } else {
      _popoverController.show();
    }
  }

  Widget _buildItemChild(
    BuildContext context,
    T item, {
    required int maxLines,
    required bool inList,
    TextStyle? style,
  }) {
    if (inList) {
      if (widget.listItemBuilder != null) {
        return widget.listItemBuilder!(context, item);
      }
      if (widget.itemBuilder != null) {
        return widget.itemBuilder!(context, item);
      }
    } else if (widget.itemBuilder != null) {
      return widget.itemBuilder!(context, item);
    }
    final key = widget.listItemKey?.call(item);
    return Text(
      widget.itemLabel!(item),
      key: key,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Widget _buildHeader(BuildContext context, AppDropdownDecoration deco) {
    if (_selected != null) {
      return _buildItemChild(
        context,
        _selected as T,
        maxLines: widget.headerMaxLines,
        inList: false,
        style: deco.headerStyle,
      );
    }
    if (widget.hintText != null) {
      return Text(
        widget.hintText!,
        maxLines: widget.headerMaxLines,
        overflow: TextOverflow.ellipsis,
        style: deco.hintStyle,
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final deco =
        widget.decoration ??
        AppDropdownDecorations.themed(
          context,
          headerFontWeight: FontWeight.w500,
          suffixIconSize: AppIconSizes.md,
        );
    final headerPadding =
        widget.closedHeaderPadding ?? kAppDropdownClosedHeaderPadding;
    final expandedPadding =
        widget.expandedHeaderPadding ?? kAppDropdownExpandedHeaderPadding;
    final itemPadding = widget.listItemPadding ?? kAppDropdownListItemPadding;
    final maxHeight = widget.overlayHeight ?? kAppDropdownDefaultOverlayHeight;

    return ListenableBuilder(
      listenable: _popoverController,
      builder: (context, _) {
        final isOpen = _popoverController.isOpen;
        final triggerPadding = isOpen ? expandedPadding : headerPadding;
        return _buildPopover(
          context,
          deco: deco,
          isOpen: isOpen,
          triggerPadding: triggerPadding,
          itemPadding: itemPadding,
          maxHeight: maxHeight,
        );
      },
    );
  }

  Widget _buildPopover(
    BuildContext context, {
    required AppDropdownDecoration deco,
    required bool isOpen,
    required EdgeInsets triggerPadding,
    required EdgeInsets itemPadding,
    required double maxHeight,
  }) {
    return AppPopover(
      controller: _popoverController,
      panelWidth: _overlayWidth,
      overlayVisible: _overlayWidth != null,
      padding: deco.menuPadding,
      decoration: deco.menuDecoration(),
      anchor: const AppAnchor(
        childAlignment: Alignment.topCenter,
        overlayAlignment: Alignment.bottomCenter,
        offset: Offset(0, 4),
      ),
      popover: (_) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: FocusScope(
            autofocus: true,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: widget.items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: kAppDropdownListItemGap),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final isSelected = _selected == item;
                return SizedBox(
                  width: double.infinity,
                  child: DropdownMenuItemButton(
                    padding: itemPadding,
                    borderRadius: deco.listItemBorderRadius,
                    highlightColor: deco.listItemHighlightColor,
                    selectedColor: deco.listItemSelectedColor,
                    isSelected: isSelected,
                    enabled: widget.enabled,
                    onTap: () {
                      setState(() => _selected = item);
                      widget.onChanged(item);
                      _popoverController.hide();
                    },
                    child: _buildItemChild(
                      context,
                      item,
                      maxLines: widget.listItemMaxLines,
                      inList: true,
                      style: deco.listItemStyle,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onTap: _toggleMenu,
          behavior: HitTestBehavior.opaque,
          child: Container(
            key: _triggerKey,
            padding: triggerPadding,
            decoration: deco.buttonDecoration(
              menuOpen: isOpen,
              isHovering: _isHovering,
            ),
            child: Row(
              children: [
                Expanded(child: _buildHeader(context, deco)),
                isOpen ? deco.expandedSuffixIcon : deco.closedSuffixIcon,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
