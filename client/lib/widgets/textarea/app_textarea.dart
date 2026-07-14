// Adapted from flutter-shadcn-ui Textarea / shadcn textarea visuals; App* naming.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_control_theme.dart';
import '../../theme/app_outline_input_theme.dart';
import '../../theme/workspace_surface_layers.dart';
import 'app_textarea_extent.dart';
import 'app_textarea_shell.dart';

export 'app_textarea_extent.dart';

/// Scroll behavior for [AppTextarea] — hides the platform scrollbar while
/// keeping mouse wheel / trackpad scrolling (ShadTextarea parity).
class AppTextareaScrollBehavior extends MaterialScrollBehavior {
  const AppTextareaScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// Multiline decoration aligned with global outline [InputDecorationTheme]
/// (same fill + border colors as single-line inputs). Clears the single-line
/// [BoxConstraints.tightFor] track height and uses textarea padding.
InputDecoration appMultilineInputDecoration(
  BuildContext context, {
  InputDecoration? decoration,
  bool hasError = false,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final inputTheme = theme.inputDecorationTheme;
  final control = AppControlTheme.fromContext(context);
  final radius = BorderRadius.circular(control.radius);
  final base = decoration ?? const InputDecoration();

  final outline = scheme.outlineVariant;

  OutlineInputBorder outlineBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );

  // Match [buildAppOutlineInputDecorationTheme] — one border layer only (no
  // outer box-shadow ring, which misaligns at rounded corners).
  OutlineInputBorder? themed(OutlineInputBorder? fromTheme, OutlineInputBorder fallback) {
    final border = fromTheme;
    if (border is OutlineInputBorder) {
      return border.copyWith(borderRadius: radius);
    }
    return fallback;
  }

  final hintBase = theme.textTheme.bodyMedium ?? theme.textTheme.bodyLarge!;
  final hintStyle = withResolvedFontSize(
    (base.hintStyle ?? inputTheme.hintStyle ?? hintBase).copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      height: 1.25,
      fontWeight: FontWeight.w400,
    ),
    sizeFrom: theme.textTheme.bodySmall ?? theme.textTheme.bodyMedium,
  );

  return base.copyWith(
    filled: base.filled ?? inputTheme.filled,
    fillColor: base.fillColor ?? inputTheme.fillColor ?? scheme.workspaceCard,
    isDense: false,
    constraints: const BoxConstraints(),
    contentPadding: base.contentPadding ?? kAppTextareaContentPadding,
    hintStyle: hintStyle,
    alignLabelWithHint: base.alignLabelWithHint ?? true,
    border: themed(
      inputTheme.border as OutlineInputBorder?,
      outlineBorder(outline),
    ),
    enabledBorder: themed(
      inputTheme.enabledBorder as OutlineInputBorder?,
      outlineBorder(hasError ? scheme.error : outline),
    ),
    focusedBorder: themed(
      inputTheme.focusedBorder as OutlineInputBorder?,
      outlineBorder(hasError ? scheme.error : scheme.primary, 1.5),
    ),
    errorBorder: themed(
      inputTheme.errorBorder as OutlineInputBorder?,
      outlineBorder(scheme.error),
    ),
    focusedErrorBorder: themed(
      inputTheme.focusedErrorBorder as OutlineInputBorder?,
      outlineBorder(scheme.error, 1.5),
    ),
    disabledBorder: themed(
      inputTheme.disabledBorder as OutlineInputBorder?,
      outlineBorder(outline.withValues(alpha: 0.38)),
    ),
  );
}

/// Material [TextField] wrapped in [AppTextareaShell] with shadcn-like chrome:
/// outline border (same as single-line inputs), muted placeholder, resize.
///
/// The field uses [TextField.expands] inside the shell so text **wraps** and
/// scrolls vertically (unlike equal `minLines`/`maxLines`, which becomes a
/// single-line input when the count is 1).
///
/// [minHeight] / [maxHeight] are **outer** shell heights including padding
/// and outline borders. Prefer [appTextareaHeightForLines] at call sites.
/// Default [minHeight] is 80 (shadcn / ShadTextarea).
class AppTextarea extends StatefulWidget {
  const AppTextarea({
    super.key,
    this.initialValue,
    this.controller,
    this.focusNode,
    this.decoration,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.showCursor,
    this.autofocus = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLength,
    this.maxLengthEnforcement,
    this.cursorWidth = 2.0,
    this.cursorHeight,
    this.cursorRadius,
    this.cursorColor,
    this.keyboardAppearance,
    this.scrollPadding = const EdgeInsets.all(20),
    this.enableInteractiveSelection,
    this.selectionControls,
    this.onTap,
    this.onTapOutside,
    this.mouseCursor,
    this.scrollController,
    this.scrollPhysics,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.scribbleEnabled = true,
    this.enableIMEPersonalizedLearning = true,
    this.contextMenuBuilder,
    this.spellCheckConfiguration,
    this.magnifierConfiguration,
    this.inputFormatters,
    this.minHeight = 80,
    this.maxHeight = 500,
    this.initialHeight,
    this.resizable = true,
    this.onHeightChanged,
    this.resizeHandleBuilder,
  }) : assert(
         initialValue == null || controller == null,
         'Cannot provide both initialValue and controller',
       );

  final String? initialValue;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final bool? showCursor;
  final bool autofocus;
  final bool enabled;
  final bool readOnly;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final double cursorWidth;
  final double? cursorHeight;
  final Radius? cursorRadius;
  final Color? cursorColor;
  final Brightness? keyboardAppearance;
  final EdgeInsets scrollPadding;
  final bool? enableInteractiveSelection;
  final TextSelectionControls? selectionControls;
  final GestureTapCallback? onTap;
  final TapRegionCallback? onTapOutside;
  final MouseCursor? mouseCursor;
  final ScrollController? scrollController;
  final ScrollPhysics? scrollPhysics;
  final Clip clipBehavior;
  final String? restorationId;
  final bool scribbleEnabled;
  final bool enableIMEPersonalizedLearning;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final TextMagnifierConfiguration? magnifierConfiguration;
  final List<TextInputFormatter>? inputFormatters;
  final double minHeight;
  final double maxHeight;
  final double? initialHeight;
  final bool resizable;
  final ValueChanged<double>? onHeightChanged;
  final WidgetBuilder? resizeHandleBuilder;

  @override
  State<AppTextarea> createState() => _AppTextareaState();
}

class _AppTextareaState extends State<AppTextarea> {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocusNode;

  TextEditingController get _controller =>
      widget.controller ?? _ownedController!;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = TextEditingController(text: widget.initialValue);
    }
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
  }

  @override
  void didUpdateWidget(covariant AppTextarea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null && oldWidget.controller != null) {
      _ownedController = TextEditingController(
        text: oldWidget.controller!.text,
      );
    } else if (widget.controller != null && oldWidget.controller == null) {
      _ownedController?.dispose();
      _ownedController = null;
    }

    if (widget.focusNode == null && oldWidget.focusNode != null) {
      _ownedFocusNode = FocusNode();
    } else if (widget.focusNode != null && oldWidget.focusNode == null) {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
  }

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  /// Non-null [InputDecoration.errorText] (including `''` for border-only).
  bool get _hasError => widget.decoration?.errorText != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final control = AppControlTheme.fromContext(context);
    final textStyle = widget.style ?? theme.textTheme.bodyMedium;
    final hasError = _hasError;
    final radius = BorderRadius.circular(control.radius);

    return AppTextareaShell(
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      initialHeight: widget.initialHeight,
      resizable: widget.resizable,
      onHeightChanged: widget.onHeightChanged,
      resizeHandleBuilder: widget.resizeHandleBuilder,
      textStyle: textStyle,
      verticalChrome: appTextareaVerticalChrome(),
      focusNode: _focusNode,
      // Fill the shell with an expanding multiline field so text wraps and
      // scrolls vertically. Do NOT use equal minLines/maxLines — when that
      // collapses to 1, Flutter becomes a single-line field (no wrap).
      builder: (context, _) {
        return ClipRRect(
          borderRadius: radius,
          child: SizedBox.expand(
            child: ScrollConfiguration(
              behavior: const AppTextareaScrollBehavior(),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: appMultilineInputDecoration(
                  context,
                  decoration: widget.decoration,
                  hasError: hasError,
                ),
                onChanged: widget.onChanged,
                onEditingComplete: widget.onEditingComplete,
                onSubmitted: widget.onSubmitted,
                style: textStyle,
                strutStyle: widget.strutStyle,
                textAlign: widget.textAlign,
                textAlignVertical: TextAlignVertical.top,
                textDirection: widget.textDirection,
                showCursor: widget.showCursor,
                autofocus: widget.autofocus,
                enabled: widget.enabled,
                readOnly: widget.readOnly,
                maxLength: widget.maxLength,
                maxLengthEnforcement: widget.maxLengthEnforcement,
                cursorWidth: widget.cursorWidth,
                cursorHeight: widget.cursorHeight,
                cursorRadius: widget.cursorRadius,
                cursorColor: widget.cursorColor ?? scheme.primary,
                keyboardAppearance: widget.keyboardAppearance,
                scrollPadding: widget.scrollPadding,
                enableInteractiveSelection: widget.enableInteractiveSelection,
                selectionControls: widget.selectionControls,
                onTap: widget.onTap,
                onTapOutside: widget.onTapOutside,
                mouseCursor:
                    widget.mouseCursor ??
                    (widget.enabled
                        ? SystemMouseCursors.text
                        : SystemMouseCursors.basic),
                scrollController: widget.scrollController,
                scrollPhysics: widget.scrollPhysics,
                clipBehavior: widget.clipBehavior,
                restorationId: widget.restorationId,
                scribbleEnabled: widget.scribbleEnabled,
                enableIMEPersonalizedLearning:
                    widget.enableIMEPersonalizedLearning,
                contextMenuBuilder: widget.contextMenuBuilder,
                spellCheckConfiguration: widget.spellCheckConfiguration,
                magnifierConfiguration: widget.magnifierConfiguration,
                inputFormatters: widget.inputFormatters,
                keyboardType: TextInputType.multiline,
                expands: true,
                minLines: null,
                maxLines: null,
              ),
            ),
          ),
        );
      },
    );
  }
}
