import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../theme/app_text_styles.dart';
import '../../utils/context_menu_position.dart';
import '../app_icon_button.dart';
import '../dropdown/popover/app_popover.dart';
import 'sidebar_action_menu_overlay.dart';

export '../dropdown/popover/app_popover.dart' show AppAnchor, AppAnchorAuto, AppGlobalAnchor, AppPopoverController;

/// Popover-backed menu controller (replaces [MenuAnchor]'s [MenuController]).
class ActionMenuController {
  ActionMenuController(this._inner);

  final AppPopoverController _inner;

  bool get isOpen => _inner.isOpen;

  void open() => _inner.show();

  void close() => _inner.hide();
}

Duration _popUpTransitionDuration(AnimationStyle? style) {
  return style?.duration ?? const Duration(milliseconds: 160);
}

Curve _popUpTransitionCurve(AnimationStyle? style) {
  return style?.curve ?? Curves.easeOutCubic;
}

/// AppFlowy-inspired action menu: rounded panel, icon rows, hover highlight,
/// optional dividers. Overlay uses [AppPopover] (portal, ~160ms scale/fade).
abstract final class SidebarActionMenuMetrics {
  static const double minWidth = 160;

  /// Legacy [MenuAnchor] allowed the panel to grow up to min × 2.
  static double maxWidthFor(double minWidth) => minWidth * 2;

  static BoxConstraints panelConstraints({
    double minWidth = SidebarActionMenuMetrics.minWidth,
    double? maxWidth,
  }) {
    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth ?? maxWidthFor(minWidth),
    );
  }

  static const double itemHeight = 34;
  static const double itemHorizontalMargin = 6;
  static const double itemPaddingLeft = 6;
  static const double itemPaddingRight = 6;
  static double iconSize(BuildContext context) => context.appIconSizes.md;
  static const double iconGap = 10;
  static const double panelPaddingTop = 12;
  static const double panelPaddingHorizontal = 8;
  static const double panelPaddingBottom = 12;
  static const double dividerVerticalPadding = 8;
  static const double itemGap = 4;
  static const BorderRadius panelRadius = BorderRadius.all(Radius.circular(8));

  static EdgeInsets get panelPadding => const EdgeInsets.fromLTRB(
    panelPaddingHorizontal,
    panelPaddingTop,
    panelPaddingHorizontal,
    panelPaddingBottom,
  );

  static BoxDecoration panelDecoration(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: cs.surfaceContainer,
      borderRadius: panelRadius,
      border: Border.all(color: cs.outlineVariant),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.1),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

bool _sidebarMenuChildUsesItemGap(Widget child) =>
    child is! SidebarActionMenuDivider;

List<Widget> _interleaveSidebarMenuItemGap(List<Widget> children) {
  if (children.length < 2) return children;
  final spaced = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    spaced.add(children[i]);
    if (i < children.length - 1 &&
        _sidebarMenuChildUsesItemGap(children[i]) &&
        _sidebarMenuChildUsesItemGap(children[i + 1])) {
      spaced.add(const SizedBox(height: SidebarActionMenuMetrics.itemGap));
    }
  }
  return spaced;
}

/// Panel container (background, padding, min width).
class SidebarActionMenuPanel extends StatelessWidget {
  const SidebarActionMenuPanel({
    super.key,
    required this.children,
    this.minWidth = SidebarActionMenuMetrics.minWidth,
    this.maxWidth,
    this.menuAnchorShell = false,
  });

  final List<Widget> children;
  final double minWidth;
  final double? maxWidth;

  /// When true, border and shadow come from the popover [decoration].
  final bool menuAnchorShell;

  @override
  Widget build(BuildContext context) {
    final content = IntrinsicWidth(
      child: ConstrainedBox(
        constraints: SidebarActionMenuMetrics.panelConstraints(
          minWidth: minWidth,
          maxWidth: maxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _interleaveSidebarMenuItemGap(children),
        ),
      ),
    );
    // Popover shell ([AppPopover]) already applies [panelPadding].
    if (menuAnchorShell) return content;
    return DecoratedBox(
      decoration: SidebarActionMenuMetrics.panelDecoration(context),
      child: Padding(
        padding: SidebarActionMenuMetrics.panelPadding,
        child: content,
      ),
    );
  }
}

/// Horizontal rule between action groups.
class SidebarActionMenuDivider extends StatelessWidget {
  const SidebarActionMenuDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: SidebarActionMenuMetrics.dividerVerticalPadding,
      ),
      child: Divider(height: 1, thickness: 1, color: cs.outlineVariant),
    );
  }
}

/// Single menu row with instant hover (no route animation).
class SidebarActionMenuItem extends StatefulWidget {
  const SidebarActionMenuItem({
    super.key,
    this.icon,
    this.iconWidget,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.menuController,
    this.tooltip,
  }) : assert(icon != null || iconWidget != null);

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;
  final ActionMenuController? menuController;
  final String? tooltip;

  @override
  State<SidebarActionMenuItem> createState() => _SidebarActionMenuItemState();
}

class _SidebarActionMenuItemState extends State<SidebarActionMenuItem> {
  var _hovered = false;

  void _handleTap() {
    if (!widget.enabled || widget.onTap == null) return;
    widget.onTap!();
    widget.menuController?.close();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverFill = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    final baseIconColor = widget.destructive
        ? cs.error
        : cs.onSurface.withValues(alpha: 0.85);
    final baseTextColor = widget.destructive ? cs.error : cs.onSurface;

    final iconColor = widget.destructive && _hovered
        ? cs.error
        : baseIconColor.withValues(
            alpha: widget.enabled ? 1 : 0.35,
          );
    final textColor = widget.destructive && _hovered
        ? cs.error
        : baseTextColor.withValues(
            alpha: widget.enabled ? 1 : 0.35,
          );

    Widget row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.enabled && widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _handleTap : null,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: SidebarActionMenuMetrics.itemHeight,
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: SidebarActionMenuMetrics.itemHorizontalMargin,
          ),
          padding: const EdgeInsets.only(
            left: SidebarActionMenuMetrics.itemPaddingLeft,
            right: SidebarActionMenuMetrics.itemPaddingRight,
          ),
          decoration: BoxDecoration(
            color: _hovered && widget.enabled && widget.onTap != null
                ? hoverFill
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              SizedBox(
                width: SidebarActionMenuMetrics.iconSize(context),
                height: SidebarActionMenuMetrics.iconSize(context),
                child: Center(
                  child:
                      widget.iconWidget ??
                      Icon(
                        widget.icon,
                        size: SidebarActionMenuMetrics.iconSize(context),
                        color: iconColor,
                      ),
                ),
              ),
              SizedBox(width: SidebarActionMenuMetrics.iconGap),
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: dropdownFieldTextStyle(
                        context,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ).copyWith(height: 18 / 14),
                    ),
                    if (widget.subtitle != null) widget.subtitle!,
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 8),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      row = Tooltip(message: widget.tooltip!, child: row);
    }

    return row;
  }
}

/// Popover anchor for custom panel content (notifications, hover menus, etc.).
class ActionMenuPopoverAnchor extends StatefulWidget {
  const ActionMenuPopoverAnchor({
    super.key,
    required this.child,
    required this.popoverBuilder,
    this.controller,
    this.anchor,
    this.onOpen,
    this.onClose,
    this.minWidth,
    this.maxWidth,
    this.fixedPanelWidth,
    this.padding,
    this.closeOnTapOutside = true,
  });

  final Widget child;
  final Widget Function(BuildContext context, ActionMenuController controller)
  popoverBuilder;
  final AppPopoverController? controller;
  final AppAnchorBase? anchor;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final double? minWidth;
  final double? maxWidth;

  /// When set, the popover panel is exactly this wide (e.g. notification dropdown).
  final double? fixedPanelWidth;
  final EdgeInsetsGeometry? padding;
  final bool closeOnTapOutside;

  @override
  State<ActionMenuPopoverAnchor> createState() =>
      _ActionMenuPopoverAnchorState();
}

class _ActionMenuPopoverAnchorState extends State<ActionMenuPopoverAnchor> {
  AppPopoverController? _ownedController;

  AppPopoverController get _popoverController =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    _ownedController = widget.controller == null
        ? AppPopoverController()
        : null;
    _popoverController.addListener(_onPopoverChanged);
  }

  @override
  void didUpdateWidget(covariant ActionMenuPopoverAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController)?.removeListener(
        _onPopoverChanged,
      );
      if (oldWidget.controller == null && widget.controller != null) {
        _ownedController?.dispose();
        _ownedController = null;
      }
      if (widget.controller == null && _ownedController == null) {
        _ownedController = AppPopoverController();
      }
      _popoverController.addListener(_onPopoverChanged);
    }
  }

  @override
  void dispose() {
    _popoverController.removeListener(_onPopoverChanged);
    _ownedController?.dispose();
    super.dispose();
  }

  void _onPopoverChanged() {
    if (_popoverController.isOpen) {
      widget.onOpen?.call();
    } else {
      widget.onClose?.call();
    }
  }

  ActionMenuController get _menuController =>
      ActionMenuController(_popoverController);

  @override
  Widget build(BuildContext context) {
    final panelMin = widget.minWidth ?? SidebarActionMenuMetrics.minWidth;
    return AppPopover(
      controller: _popoverController,
      closeOnTapOutside: widget.closeOnTapOutside,
      anchor:
          widget.anchor ??
          const AppAnchor(
            childAlignment: Alignment.topLeft,
            overlayAlignment: Alignment.bottomLeft,
            offset: Offset(0, 4),
          ),
      decoration: SidebarActionMenuMetrics.panelDecoration(context),
      panelWidth: widget.fixedPanelWidth,
      padding: widget.padding ?? SidebarActionMenuMetrics.panelPadding,
      popover: (ctx) {
        final panel = widget.popoverBuilder(ctx, _menuController);
        if (widget.fixedPanelWidth != null) return panel;
        return IntrinsicWidth(
          child: ConstrainedBox(
            constraints: SidebarActionMenuMetrics.panelConstraints(
              minWidth: panelMin,
              maxWidth: widget.maxWidth,
            ),
            child: panel,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Icon button that opens an [AppPopover] action menu.
class SidebarActionMenuIconAnchor extends StatefulWidget {
  const SidebarActionMenuIconAnchor({
    super.key,
    this.icon,
    this.triggerBuilder,
    required this.buildMenuChildren,
    this.onOpen,
    this.onClose,
    this.size = AppIconButton.kDefaultSize,
    this.minWidth = SidebarActionMenuMetrics.minWidth,
    this.anchor,
  }) : assert(icon != null || triggerBuilder != null);

  final Widget? icon;
  final Widget Function(BuildContext context, ActionMenuController controller)?
  triggerBuilder;
  final List<Widget> Function(
    BuildContext context,
    ActionMenuController controller,
  )
  buildMenuChildren;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final double size;
  final double minWidth;
  final AppAnchorBase? anchor;

  @override
  State<SidebarActionMenuIconAnchor> createState() =>
      _SidebarActionMenuIconAnchorState();
}

class _SidebarActionMenuIconAnchorState
    extends State<SidebarActionMenuIconAnchor> {
  final _popoverController = AppPopoverController();

  @override
  void initState() {
    super.initState();
    _popoverController.addListener(_onPopoverChanged);
  }

  @override
  void dispose() {
    _popoverController.removeListener(_onPopoverChanged);
    _popoverController.dispose();
    super.dispose();
  }

  void _onPopoverChanged() {
    if (_popoverController.isOpen) {
      widget.onOpen?.call();
    } else {
      widget.onClose?.call();
    }
  }

  ActionMenuController get _menuController =>
      ActionMenuController(_popoverController);

  @override
  Widget build(BuildContext context) {
    final menuController = _menuController;
    return AppPopover(
      controller: _popoverController,
      anchor:
          widget.anchor ??
          const AppAnchor(
            childAlignment: Alignment.topLeft,
            overlayAlignment: Alignment.bottomLeft,
            offset: Offset(0, 4),
          ),
      decoration: SidebarActionMenuMetrics.panelDecoration(context),
      padding: SidebarActionMenuMetrics.panelPadding,
      popover: (ctx) => SidebarActionMenuPanel(
        minWidth: widget.minWidth,
        menuAnchorShell: true,
        children: widget.buildMenuChildren(ctx, menuController),
      ),
      child: widget.triggerBuilder != null
          ? widget.triggerBuilder!(context, menuController)
          : AppIconButton(
              iconWidget: widget.icon,
              size: widget.size,
              onTap: _popoverController.toggle,
            ),
    );
  }
}

int sidebarActionMenuSpecGapCount(List<SidebarActionMenuSpec> specs) {
  var gaps = 0;
  var previousWasItem = false;
  for (final spec in specs) {
    if (spec.isDivider) {
      previousWasItem = false;
      continue;
    }
    if (previousWasItem) gaps++;
    previousWasItem = true;
  }
  return gaps;
}

double estimateSidebarActionMenuHeight({
  required int itemCount,
  int dividerCount = 0,
  int itemGapCount = 0,
}) {
  final gaps = itemGapCount > 0
      ? itemGapCount
      : (itemCount > 1 ? itemCount - 1 : 0);
  return SidebarActionMenuMetrics.panelPaddingTop +
      SidebarActionMenuMetrics.panelPaddingBottom +
      itemCount * SidebarActionMenuMetrics.itemHeight +
      gaps * SidebarActionMenuMetrics.itemGap +
      dividerCount * (SidebarActionMenuMetrics.dividerVerticalPadding * 2 + 1);
}

class SidebarActionMenuSpec {
  const SidebarActionMenuSpec.divider()
    : isDivider = true,
      value = null,
      icon = null,
      label = null,
      subtitle = null,
      trailing = null,
      destructive = false,
      enabled = true,
      selected = false,
      onAction = null,
      tooltip = null;

  const SidebarActionMenuSpec.item({
    this.value,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.destructive = false,
    this.enabled = true,
    this.selected = false,
    this.onAction,
    this.tooltip,
  }) : isDivider = false;

  final bool isDivider;
  final Object? value;
  final IconData? icon;
  final String? label;
  final Widget? subtitle;
  final Widget? trailing;
  final bool destructive;
  final bool enabled;
  final bool selected;
  final VoidCallback? onAction;
  final String? tooltip;
}

int sidebarActionMenuSpecItemCount(List<SidebarActionMenuSpec> specs) =>
    specs.where((s) => !s.isDivider).length;

int sidebarActionMenuSpecDividerCount(List<SidebarActionMenuSpec> specs) =>
    specs.where((s) => s.isDivider).length;

List<Widget> buildSidebarActionMenuChildren({
  required BuildContext context,
  required List<SidebarActionMenuSpec> specs,
  required ActionMenuController menuController,
  required ValueChanged<Object?> onSelect,
}) {
  return specs.map((spec) {
    if (spec.isDivider) return const SidebarActionMenuDivider();
    return _specToMenuItem(
      context: context,
      spec: spec,
      menuController: menuController,
      onSelect: onSelect,
    );
  }).toList();
}

Widget _specToMenuItem({
  required BuildContext context,
  required SidebarActionMenuSpec spec,
  ActionMenuController? menuController,
  ValueChanged<Object?>? onSelect,
  void Function(Object? value)? onChosen,
}) {
  final trailing = spec.selected
      ? Icon(
          Icons.check,
          size: context.appIconSizes.md,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        )
      : spec.trailing;

  VoidCallback? onTap;
  if (spec.enabled) {
    onTap = () {
      spec.onAction?.call();
      onChosen?.call(spec.value);
      onSelect?.call(spec.value);
      menuController?.close();
    };
  }

  return SidebarActionMenuItem(
    icon: spec.icon,
    label: spec.label ?? '',
    subtitle: spec.subtitle,
    trailing: trailing,
    destructive: spec.destructive,
    enabled: spec.enabled,
    tooltip: spec.tooltip,
    menuController: menuController,
    onTap: onTap,
  );
}

class SidebarActionMenuButton extends StatelessWidget {
  const SidebarActionMenuButton({
    super.key,
    required this.specs,
    required this.onSelected,
    this.icon,
    this.triggerBuilder,
    this.onOpen,
    this.onClose,
    this.size = AppIconButton.kDefaultSize,
    this.minWidth = SidebarActionMenuMetrics.minWidth,
    this.tooltip,
  });

  final List<SidebarActionMenuSpec> specs;
  final ValueChanged<Object?> onSelected;
  final Widget? icon;
  final Widget Function(BuildContext context, ActionMenuController controller)?
  triggerBuilder;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final double size;
  final double minWidth;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final anchor = SidebarActionMenuIconAnchor(
      icon: triggerBuilder == null
          ? (icon ?? Icon(Icons.more_horiz, size: context.appIconSizes.md))
          : null,
      triggerBuilder: triggerBuilder,
      size: size,
      minWidth: minWidth,
      onOpen: onOpen,
      onClose: onClose,
      buildMenuChildren: (context, controller) =>
          buildSidebarActionMenuChildren(
            context: context,
            specs: specs,
            menuController: controller,
            onSelect: onSelected,
          ),
    );
    if (tooltip == null || tooltip!.isEmpty) return anchor;
    return Tooltip(message: tooltip!, child: anchor);
  }
}

Future<T?> _showActionMenuFromSpecs<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<SidebarActionMenuSpec> specs,
  double minWidth = SidebarActionMenuMetrics.minWidth,
  bool useRootNavigator = true,
  AnimationStyle? popUpAnimationStyle,
}) {
  return showFloatingActionMenuOverlay<T>(
    context: context,
    globalPosition: globalPosition,
    useRootNavigator: useRootNavigator,
    transitionDuration: _popUpTransitionDuration(popUpAnimationStyle),
    transitionCurve: _popUpTransitionCurve(popUpAnimationStyle),
    menuBuilder: (overlayContext, complete) {
      return DecoratedBox(
        decoration: SidebarActionMenuMetrics.panelDecoration(overlayContext),
        child: Padding(
          padding: SidebarActionMenuMetrics.panelPadding,
          child: SidebarActionMenuPanel(
            minWidth: minWidth,
            menuAnchorShell: true,
            children: specs.map((spec) {
              if (spec.isDivider) return const SidebarActionMenuDivider();
              return _specToMenuItem(
                context: overlayContext,
                spec: spec,
                onChosen: (value) => complete(value as T?),
              );
            }).toList(),
          ),
        ),
      );
    },
  );
}

Future<T?> showSidebarActionMenuFromSpecs<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<SidebarActionMenuSpec> specs,
  double minWidth = SidebarActionMenuMetrics.minWidth,
  bool useRootNavigator = true,
  AnimationStyle? popUpAnimationStyle,
}) {
  return _showActionMenuFromSpecs<T>(
    context: context,
    globalPosition: globalPosition,
    specs: specs,
    minWidth: minWidth,
    useRootNavigator: useRootNavigator,
    popUpAnimationStyle: popUpAnimationStyle,
  );
}

Future<T?> showSidebarActionMenuFromSpecsAtTap<T>({
  required BuildContext context,
  required TapDownDetails tapDetails,
  required List<SidebarActionMenuSpec> specs,
  double minWidth = SidebarActionMenuMetrics.minWidth,
  bool useRootNavigator = true,
  AnimationStyle? popUpAnimationStyle,
}) {
  return showSidebarActionMenuFromSpecs<T>(
    context: context,
    globalPosition: contextMenuGlobalPosition(context, tapDetails),
    specs: specs,
    minWidth: minWidth,
    useRootNavigator: useRootNavigator,
    popUpAnimationStyle: popUpAnimationStyle,
  );
}

Future<T?> _showActionMenuWithChildren<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<Widget> children,
  double minWidth = SidebarActionMenuMetrics.minWidth,
  bool useRootNavigator = true,
  AnimationStyle? popUpAnimationStyle,
}) {
  return showFloatingActionMenuOverlay<T>(
    context: context,
    globalPosition: globalPosition,
    useRootNavigator: useRootNavigator,
    transitionDuration: _popUpTransitionDuration(popUpAnimationStyle),
    transitionCurve: _popUpTransitionCurve(popUpAnimationStyle),
    menuBuilder: (overlayContext, complete) {
      return _ActionMenuOverlayScope<T>(
        onChosen: complete,
        child: DecoratedBox(
          decoration: SidebarActionMenuMetrics.panelDecoration(overlayContext),
          child: Padding(
            padding: SidebarActionMenuMetrics.panelPadding,
            child: SidebarActionMenuPanel(
              minWidth: minWidth,
              menuAnchorShell: true,
              children: children,
            ),
          ),
        ),
      );
    },
  );
}

class _ActionMenuOverlayScope<T> extends InheritedWidget {
  const _ActionMenuOverlayScope({
    required this.onChosen,
    required super.child,
  });

  final void Function(T? value) onChosen;

  static _ActionMenuOverlayScope<T>? maybeOf<T>(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ActionMenuOverlayScope<T>>();
  }

  @override
  bool updateShouldNotify(_ActionMenuOverlayScope<T> oldWidget) => false;
}

/// Shows an action menu at [globalPosition] with pre-built row widgets.
Future<T?> showSidebarActionMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<Widget> children,
  double minWidth = SidebarActionMenuMetrics.minWidth,
  int itemCount = 4,
  int dividerCount = 0,
  int? itemGapCount,
  bool useRootNavigator = true,
  AnimationStyle? popUpAnimationStyle,
}) {
  return _showActionMenuWithChildren<T>(
    context: context,
    globalPosition: globalPosition,
    children: children,
    minWidth: minWidth,
    useRootNavigator: useRootNavigator,
    popUpAnimationStyle: popUpAnimationStyle,
  );
}

Future<T?> showSidebarActionMenuAtTap<T>({
  required BuildContext context,
  required TapDownDetails tapDetails,
  required List<Widget> children,
  double minWidth = SidebarActionMenuMetrics.minWidth,
  int itemCount = 4,
  int dividerCount = 0,
  int? itemGapCount,
  bool useRootNavigator = true,
  AnimationStyle? popUpAnimationStyle,
}) {
  return showSidebarActionMenu<T>(
    context: context,
    globalPosition: contextMenuGlobalPosition(context, tapDetails),
    children: children,
    minWidth: minWidth,
    useRootNavigator: useRootNavigator,
    popUpAnimationStyle: popUpAnimationStyle,
  );
}

class SidebarActionMenuPopupItem<T> extends StatelessWidget {
  const SidebarActionMenuPopupItem({
    super.key,
    required this.value,
    this.icon,
    this.iconWidget,
    required this.label,
    this.destructive = false,
    this.enabled = true,
    this.tooltip,
  }) : assert(icon != null || iconWidget != null);

  final T value;
  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final bool destructive;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scope = _ActionMenuOverlayScope.maybeOf<T>(context);
    return SidebarActionMenuItem(
      icon: icon,
      iconWidget: iconWidget,
      label: label,
      destructive: destructive,
      enabled: enabled,
      tooltip: tooltip,
      onTap: enabled ? () => scope?.onChosen(value) : null,
    );
  }
}
