import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import 'app_dropdown_decoration.dart';
import 'app_dropdown_item_filter.dart';
import 'app_dropdown_search_field.dart';
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
    this.onEmptyTap,
    this.closedHeaderPadding,
    this.expandedHeaderPadding,
    this.listItemPadding,
    this.listItemKey,
    this.controller,
    this.searchable = true,
    this.searchHintText,
    this.emptySearchText,
    this.itemSearchText,
    this.filterPredicate,
    this.searchMinItems = 8,
    this.clearSearchOnClose = true,
    this.onSearchChanged,
    this.onHighlightChanged,
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
  final VoidCallback? onEmptyTap;
  final EdgeInsets? closedHeaderPadding;
  final EdgeInsets? expandedHeaderPadding;
  final EdgeInsets? listItemPadding;
  final Key? Function(T item)? listItemKey;
  final AppPopoverController? controller;

  /// When true, shows a shadcn Combobox-style search field above the option list.
  final bool searchable;

  /// Placeholder for the overlay search field (defaults to l10n).
  final String? searchHintText;

  /// Shown when the query filters out every option (defaults to l10n).
  final String? emptySearchText;

  /// Text used for search when [itemLabel] is absent or insufficient.
  final String Function(T item)? itemSearchText;

  /// Custom match predicate; receives the raw query string (not normalized).
  final bool Function(T item, String query)? filterPredicate;

  /// Only show search when [items].length is at least this value (0 = always).
  final int searchMinItems;

  /// Clears the overlay search field when the menu closes (shadcn default).
  final bool clearSearchOnClose;

  /// Notified when the overlay search query changes.
  final ValueChanged<String>? onSearchChanged;

  /// Fires with the item the pointer is hovering in the open menu, or `null`
  /// when the menu closes. Exit between rows does not clear (last hover sticks
  /// until another enter or close) so consumers can preview without flicker.
  final ValueChanged<T?>? onHighlightChanged;

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
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';

  /// Measured trigger width for the overlay panel. Updated after layout only —
  /// never read [RenderBox] during [build] or constrain the trigger from it.
  double? _overlayWidth;

  bool get _showsSearch =>
      widget.searchable && widget.items.length >= widget.searchMinItems;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _popoverController = widget.controller ?? AppPopoverController();
    _popoverController.addListener(_onPopoverChanged);
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
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
    _searchController.dispose();
    _searchFocusNode.dispose();
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
        if (_showsSearch) {
          _searchFocusNode.requestFocus();
        }
      } else {
        _onPopoverClosed();
      }
    });
  }

  void _onPopoverClosed() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
    if (widget.clearSearchOnClose) {
      _clearSearch();
    }
    widget.onHighlightChanged?.call(null);
  }

  void _clearSearch() {
    final hadQuery =
        _searchQuery.isNotEmpty || _searchController.text.isNotEmpty;
    _searchController.clear();
    if (_searchQuery.isNotEmpty) {
      _searchQuery = '';
      if (mounted) setState(() {});
    }
    if (hadQuery) {
      widget.onSearchChanged?.call('');
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query);
    widget.onSearchChanged?.call(query);
  }

  String _searchTextFor(T item) {
    if (widget.itemSearchText != null) {
      return widget.itemSearchText!(item);
    }
    if (widget.itemLabel != null) {
      return widget.itemLabel!(item);
    }
    if (item is String) {
      return item;
    }
    return item.toString();
  }

  bool _matchesSearch(T item) {
    if (widget.filterPredicate != null) {
      return widget.filterPredicate!(item, _searchQuery);
    }
    return appDropdownItemMatchesQuery(
      query: _searchQuery,
      searchText: _searchTextFor(item),
    );
  }

  bool get _hasActiveSearchQuery =>
      _showsSearch && _searchQuery.trim().isNotEmpty;

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
    if (widget.items.isEmpty) {
      widget.onEmptyTap?.call();
      return;
    }
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
          suffixIconSize: context.appIconSizes.md,
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
      popover: (popoverContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: FocusScope(
            autofocus: !_showsSearch,
            child: _buildPopoverBody(
              popoverContext,
              deco: deco,
              itemPadding: itemPadding,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final expand = constraints.hasBoundedWidth;
                return Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (expand)
                      Expanded(child: _buildHeader(context, deco))
                    else
                      Flexible(
                        fit: FlexFit.loose,
                        child: _buildHeader(context, deco),
                      ),
                    isOpen ? deco.expandedSuffixIcon : deco.closedSuffixIcon,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopoverBody(
    BuildContext context, {
    required AppDropdownDecoration deco,
    required EdgeInsets itemPadding,
  }) {
    final list = _showsSearch
        ? _buildSearchableList(context, deco: deco, itemPadding: itemPadding)
        : _buildPlainList(context, deco: deco, itemPadding: itemPadding);

    if (!_showsSearch) {
      return list;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownSearchField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          hintText: widget.searchHintText ?? context.l10n.appDropdownSearchHint,
          onChanged: _onSearchChanged,
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 4),
        Expanded(child: list),
      ],
    );
  }

  Widget _buildPlainList(
    BuildContext context, {
    required AppDropdownDecoration deco,
    required EdgeInsets itemPadding,
  }) {
    // Bounded by the popover [ConstrainedBox]; avoid shrinkWrap so only
    // visible rows are built/laid out (font pickers can have hundreds).
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: widget.items.length,
      separatorBuilder: (_, _) =>
          const SizedBox(height: kAppDropdownListItemGap),
      itemBuilder: (context, index) {
        return _buildListItem(
          context,
          item: widget.items[index],
          deco: deco,
          itemPadding: itemPadding,
        );
      },
    );
  }

  /// Filtered lazy list. Search focus is owned by the field above — do not
  /// keep every option in the tree via [Offstage] (that forced full-list
  /// layout and multi-second jank on large catalogs).
  Widget _buildSearchableList(
    BuildContext context, {
    required AppDropdownDecoration deco,
    required EdgeInsets itemPadding,
  }) {
    final visible = <T>[
      for (final item in widget.items)
        if (!_hasActiveSearchQuery || _matchesSearch(item)) item,
    ];
    final showEmptyState = _hasActiveSearchQuery && visible.isEmpty;

    if (showEmptyState) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: itemPadding,
            child: Text(
              widget.emptySearchText ?? context.l10n.appDropdownSearchNoResults,
              style: deco.hintStyle,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: visible.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == visible.length - 1 ? 0 : kAppDropdownListItemGap,
          ),
          child: _buildListItem(
            context,
            item: visible[index],
            deco: deco,
            itemPadding: itemPadding,
          ),
        );
      },
    );
  }

  Widget _buildListItem(
    BuildContext context, {
    required T item,
    required AppDropdownDecoration deco,
    required EdgeInsets itemPadding,
  }) {
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
        onHoverChanged: (hovering) {
          if (hovering) widget.onHighlightChanged?.call(item);
        },
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
  }
}
