import 'package:flutter/material.dart';
import 'package:panes/src/multi_pane.dart';
import 'package:panes/src/pane_controller.dart';
import 'package:panes/src/pane_entry.dart';
import 'package:panes/src/pane_size.dart';

export 'package:panes/src/pane_entry.dart' show ResizeBehavior;

/// Represents the different panes in an [IdeLayout].
enum IdePane {
  /// The left sidebar pane.
  left('left'),

  /// The right sidebar pane.
  right('right'),

  /// The bottom pane (terminal, logs, etc.).
  bottom('bottom'),

  /// The main center/editor area.
  center('center'),

  /// The center container pane that holds the editor and bottom panel.
  centerContainer('centerContainer');

  /// The string identifier for this pane.
  final String id;

  const IdePane(this.id);
}

/// A controller for the [IdeLayout] widget.
///
/// Manages the state and visibility of the standard IDE-like panes:
/// left, right, center (editor), and bottom.
class IdeController {
  /// The controller for the horizontal axis (Left | Center | Right).
  late final PaneController rootController;

  /// The controller for the vertical axis (Editor | Bottom) within the center pane.
  late final PaneController centerController;

  /// Creates an [IdeController] with customizable panel settings.
  ///
  /// All size parameters accept [PaneSize] values, which can be either
  /// [PaneSize.pixel] for fixed pixel sizes or [PaneSize.fraction] for
  /// proportional sizes.
  IdeController({
    // Left panel configuration
    PaneSize? leftSize,
    PaneSize? leftMinSize,
    PaneSize? leftMaxSize,
    bool leftAutoHide = true,
    PaneSize? leftAutoHideThreshold,
    bool leftVisible = true,
    ResizeBehavior? leftResizeBehavior,

    // Right panel configuration
    PaneSize? rightSize,
    PaneSize? rightMinSize,
    PaneSize? rightMaxSize,
    bool rightAutoHide = true,
    PaneSize? rightAutoHideThreshold,
    bool rightVisible = false,
    ResizeBehavior? rightResizeBehavior,

    // Bottom panel configuration
    PaneSize? bottomSize,
    PaneSize? bottomMinSize,
    PaneSize? bottomMaxSize,
    bool bottomAutoHide = true,
    PaneSize? bottomAutoHideThreshold,
    bool bottomVisible = false,
    ResizeBehavior? bottomResizeBehavior,
  }) {
    // Horizontal: Left | Center | Right
    rootController = PaneController(
      entries: [
        PaneEntry(
          id: IdePane.left.id,
          initialSize: leftSize ?? PaneSize.pixel(250),
          minSize: leftMinSize ?? PaneSize.pixel(100),
          maxSize: leftMaxSize,
          autoHide: leftAutoHide,
          autoHideThreshold: leftAutoHideThreshold ?? PaneSize.fraction(0.5),
          visible: leftVisible,
          resizeBehavior: leftResizeBehavior,
        ),
        PaneEntry(
          id: IdePane.centerContainer.id,
          initialSize: PaneSize.fraction(1.0),
        ),
        PaneEntry(
          id: IdePane.right.id,
          initialSize: rightSize ?? PaneSize.pixel(300),
          minSize: rightMinSize ?? PaneSize.pixel(200),
          maxSize: rightMaxSize,
          autoHide: rightAutoHide,
          autoHideThreshold: rightAutoHideThreshold ?? PaneSize.fraction(0.5),
          visible: rightVisible,
          resizeBehavior: rightResizeBehavior,
        ),
      ],
    );

    // Vertical: Editor | Bottom
    centerController = PaneController(
      entries: [
        PaneEntry(
          id: IdePane.center.id,
          initialSize: PaneSize.fraction(1.0),
        ),
        PaneEntry(
          id: IdePane.bottom.id,
          initialSize: bottomSize ?? PaneSize.pixel(240),
          minSize: bottomMinSize ?? PaneSize.pixel(50),
          maxSize: bottomMaxSize,
          autoHide: bottomAutoHide,
          autoHideThreshold: bottomAutoHideThreshold ?? PaneSize.fraction(0.5),
          visible: bottomVisible,
          resizeBehavior: bottomResizeBehavior,
        ),
      ],
    );
  }

  /// Toggles the visibility of the left panel.
  void toggleLeft() => rootController.toggle(IdePane.left.id);

  /// Toggles the visibility of the right panel.
  void toggleRight() => rootController.toggle(IdePane.right.id);

  /// Toggles the visibility of the bottom panel.
  void toggleBottom() => centerController.toggle(IdePane.bottom.id);

  /// Saves the current layout state (sizes and visibility) to a map.
  Map<String, dynamic> save() {
    return {
      'root': rootController.save(),
      'center': centerController.save(),
    };
  }

  /// Loads the layout state from a map.
  void load(Map<String, dynamic> data) {
    if (data.containsKey('root')) {
      rootController.load(Map<String, dynamic>.from(data['root']));
    }
    if (data.containsKey('center')) {
      centerController.load(Map<String, dynamic>.from(data['center']));
    }
  }

  /// Disposes both the root and center controllers.
  ///
  /// Call this when the [IdeController] is no longer needed to free resources.
  void dispose() {
    rootController.dispose();
    centerController.dispose();
  }
}

/// Callback signature for when a pane's visibility state changes.
typedef IdePaneStateChangedCallback = void Function(
  IdePane pane,
  bool isVisible,
);

/// Callback signature for when the maximize state changes.
typedef IdeMaximizeStateChangedCallback = void Function(
  bool isMaximized,
);

/// Callback signature for when a pane's size changes.
typedef IdeSizeChangedCallback = void Function(
  IdePane pane,
  double size,
);

/// Builder for an IDE pane, exposing its animation progress (0.0 to 1.0).
typedef IdePaneBuilder = Widget Function(
    BuildContext context, double animationProgress);

/// A pre-configured layout widget that mimics a standard IDE.
///
/// It provides slots for [leftPanelBuilder], [rightPanelBuilder], [bottomPanelBuilder],
/// and [centerBuilder] (editor), managed by an [IdeController].
class IdeLayout extends StatefulWidget {
  /// The controller that manages the state of this layout.
  final IdeController controller;

  /// Builder for the left sidebar panel.
  final IdePaneBuilder? leftPanelBuilder;

  /// Builder for the right sidebar panel.
  final IdePaneBuilder? rightPanelBuilder;

  /// Builder for the bottom panel.
  final IdePaneBuilder? bottomPanelBuilder;

  /// Builder for the main center/editor area.
  final IdePaneBuilder? centerBuilder;

  /// Duration for panel resize/toggle animations.
  final Duration animationDuration;

  /// Callback invoked when any pane's visibility state changes.
  final IdePaneStateChangedCallback? onPaneStateChanged;

  /// Callback invoked when the maximize state changes.
  ///
  /// Returns true when the editor is fully maximized (both root and center
  /// controllers are in maximized state).
  final IdeMaximizeStateChangedCallback? onMaximizeStateChanged;

  /// Callback invoked when any pane's size changes.
  ///
  /// This is called whenever a pane is resized, providing realtime size updates.
  final IdeSizeChangedCallback? onSizeChanged;

  /// Creates an [IdeLayout].
  const IdeLayout({
    super.key,
    required this.controller,
    this.leftPanelBuilder,
    this.rightPanelBuilder,
    this.bottomPanelBuilder,
    this.centerBuilder,
    this.animationDuration = const Duration(milliseconds: 250),
    this.onPaneStateChanged,
    this.onMaximizeStateChanged,
    this.onSizeChanged,
  });

  @override
  State<IdeLayout> createState() => _IdeLayoutState();
}

class _IdeLayoutState extends State<IdeLayout> {
  late Map<String, bool> _previousVisibility;
  late bool _previousMaximized;
  late Map<String, double?> _previousSizes;

  @override
  void initState() {
    super.initState();
    _previousVisibility = _captureVisibility();
    _previousMaximized = _isFullyMaximized();
    _previousSizes = _captureSizes();
    widget.controller.rootController.addListener(_onControllerChanged);
    widget.controller.centerController.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(IdeLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.rootController.removeListener(_onControllerChanged);
      oldWidget.controller.centerController
          .removeListener(_onControllerChanged);
      _previousVisibility = _captureVisibility();
      _previousMaximized = _isFullyMaximized();
      _previousSizes = _captureSizes();
      widget.controller.rootController.addListener(_onControllerChanged);
      widget.controller.centerController.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.rootController.removeListener(_onControllerChanged);
    widget.controller.centerController.removeListener(_onControllerChanged);
    super.dispose();
  }

  Map<String, bool> _captureVisibility() {
    return {
      IdePane.left.id:
          widget.controller.rootController.isVisible(IdePane.left.id),
      IdePane.right.id:
          widget.controller.rootController.isVisible(IdePane.right.id),
      IdePane.bottom.id:
          widget.controller.centerController.isVisible(IdePane.bottom.id),
      IdePane.center.id:
          widget.controller.centerController.isVisible(IdePane.center.id),
    };
  }

  Map<String, double?> _captureSizes() {
    return {
      IdePane.left.id:
          widget.controller.rootController.getVisualPixelSize(IdePane.left.id),
      IdePane.right.id:
          widget.controller.rootController.getVisualPixelSize(IdePane.right.id),
      IdePane.bottom.id: widget.controller.centerController
          .getVisualPixelSize(IdePane.bottom.id),
    };
  }

  bool _isFullyMaximized() {
    return widget.controller.rootController.isMaximized &&
        widget.controller.centerController.isMaximized;
  }

  void _onControllerChanged() {
    _checkAndNotifyVisibilityChanges();
    _checkAndNotifyMaximizeChanges();
    _checkAndNotifySizeChanges();
  }

  void _checkAndNotifyVisibilityChanges() {
    final callback = widget.onPaneStateChanged;
    if (callback == null) return;

    final current = _captureVisibility();

    final leftVisible = current[IdePane.left.id];
    final rightVisible = current[IdePane.right.id];
    final bottomVisible = current[IdePane.bottom.id];
    final centerVisible = current[IdePane.center.id];

    if (leftVisible != _previousVisibility[IdePane.left.id] &&
        leftVisible != null) {
      callback(IdePane.left, leftVisible);
    }
    if (rightVisible != _previousVisibility[IdePane.right.id] &&
        rightVisible != null) {
      callback(IdePane.right, rightVisible);
    }
    if (bottomVisible != _previousVisibility[IdePane.bottom.id] &&
        bottomVisible != null) {
      callback(IdePane.bottom, bottomVisible);
    }
    if (centerVisible != _previousVisibility[IdePane.center.id] &&
        centerVisible != null) {
      callback(IdePane.center, centerVisible);
    }

    _previousVisibility = current;
  }

  void _checkAndNotifyMaximizeChanges() {
    final callback = widget.onMaximizeStateChanged;
    if (callback == null) return;

    final currentMaximized = _isFullyMaximized();
    if (currentMaximized != _previousMaximized) {
      callback(currentMaximized);
      _previousMaximized = currentMaximized;
    }
  }

  void _checkAndNotifySizeChanges() {
    final callback = widget.onSizeChanged;
    if (callback == null) return;

    final current = _captureSizes();

    final leftSize = current[IdePane.left.id];
    final rightSize = current[IdePane.right.id];
    final bottomSize = current[IdePane.bottom.id];

    if (leftSize != _previousSizes[IdePane.left.id] && leftSize != null) {
      callback(IdePane.left, leftSize);
    }
    if (rightSize != _previousSizes[IdePane.right.id] && rightSize != null) {
      callback(IdePane.right, rightSize);
    }
    if (bottomSize != _previousSizes[IdePane.bottom.id] && bottomSize != null) {
      callback(IdePane.bottom, bottomSize);
    }

    _previousSizes = current;
  }

  @override
  Widget build(BuildContext context) {
    return MultiPane(
      direction: Axis.horizontal,
      controller: widget.controller.rootController,
      animationDuration: widget.animationDuration,
      paneBuilder: (context, id, progress) {
        if (id == IdePane.left.id) {
          return widget.leftPanelBuilder?.call(context, progress) ??
              const SizedBox.shrink();
        }

        if (id == IdePane.right.id) {
          return widget.rightPanelBuilder?.call(context, progress) ??
              const SizedBox();
        }

        if (id == IdePane.centerContainer.id) {
          return MultiPane(
            direction: Axis.vertical,
            controller: widget.controller.centerController,
            animationDuration: widget.animationDuration,
            paneBuilder: (context, innerId, innerProgress) {
              if (innerId == IdePane.center.id) {
                return widget.centerBuilder?.call(context, innerProgress) ??
                    const SizedBox.shrink();
              }
              if (innerId == IdePane.bottom.id) {
                return widget.bottomPanelBuilder
                        ?.call(context, innerProgress) ??
                    const SizedBox();
              }
              return const SizedBox();
            },
          );
        }

        return const SizedBox();
      },
    );
  }
}
