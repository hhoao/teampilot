// Adapted from flutter-shadcn-ui Textarea / shadcn textarea visuals; App* naming.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_control_theme.dart';
import '../../theme/app_outline_input_theme.dart';
import 'app_textarea_extent.dart';
import 'app_textarea_shell.dart';

export 'app_textarea_extent.dart';

/// Multiline decoration styled like shadcn Textarea (soft border, muted hint,
/// px-3/py-2). Clears the global single-line [BoxConstraints.tightFor] track.
///
/// Focus ring is painted by [AppTextarea] (not by [OutlineInputBorder]).
InputDecoration appMultilineInputDecoration(
  BuildContext context, {
  InputDecoration? decoration,
  bool focused = false,
  bool hasError = false,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final control = AppControlTheme.fromContext(context);
  final radius = BorderRadius.circular(control.radius);
  final base = decoration ?? const InputDecoration();

  final borderColor = hasError
      ? scheme.error
      : focused
      ? scheme.outline
      : scheme.outlineVariant;
  final borderWidth = focused || hasError ? 1.0 : 1.0;

  OutlineInputBorder outline([Color? color]) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: color ?? borderColor, width: borderWidth),
  );

  final hintBase = theme.textTheme.bodyMedium ?? theme.textTheme.bodyLarge!;
  final hintStyle = withResolvedFontSize(
    (base.hintStyle ?? hintBase).copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
      height: 1.25,
      fontWeight: FontWeight.w400,
    ),
    sizeFrom: theme.textTheme.bodySmall ?? theme.textTheme.bodyMedium,
  );

  return base.copyWith(
    filled: base.filled ?? true,
    fillColor: base.fillColor ?? scheme.surface,
    isDense: true,
    // Empty constraints override theme `tightFor(height: control.height)`.
    constraints: const BoxConstraints(),
    contentPadding:
        base.contentPadding ??
        const EdgeInsets.symmetric(
          horizontal: kAppTextareaHorizontalPadding,
          vertical: kAppTextareaVerticalPadding,
        ),
    hintStyle: hintStyle,
    alignLabelWithHint: base.alignLabelWithHint ?? true,
    border: outline(scheme.outlineVariant),
    enabledBorder: outline(
      hasError ? scheme.error : scheme.outlineVariant,
    ),
    focusedBorder: outline(hasError ? scheme.error : scheme.outline),
    errorBorder: outline(scheme.error),
    focusedErrorBorder: outline(scheme.error),
    disabledBorder: outline(scheme.outlineVariant.withValues(alpha: 0.38)),
  );
}

/// Material [TextField] wrapped in [AppTextareaShell] with shadcn-like chrome:
/// soft border, focus ring, muted placeholder, fixed viewport + drag resize.
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
    _focusNode.addListener(_handleFocusChange);
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

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      if (oldWidget.focusNode == null) {
        _ownedFocusNode?.removeListener(_handleFocusChange);
      }
      if (widget.focusNode == null) {
        _ownedFocusNode ??= FocusNode();
        _ownedFocusNode!.addListener(_handleFocusChange);
      } else {
        if (oldWidget.focusNode == null) {
          _ownedFocusNode?.dispose();
          _ownedFocusNode = null;
        }
        widget.focusNode!.addListener(_handleFocusChange);
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _ownedFocusNode?.dispose();
    _ownedController?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  /// Non-null [InputDecoration.errorText] (including `''` for border-only).
  bool get _hasError => widget.decoration?.errorText != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final control = AppControlTheme.fromContext(context);
    final textStyle = widget.style ?? theme.textTheme.bodyMedium;
    final focused = _focusNode.hasFocus && widget.enabled;
    final hasError = _hasError;
    final radius = BorderRadius.circular(control.radius);

    final ringColor = hasError
        ? scheme.error.withValues(alpha: 0.2)
        : scheme.primary.withValues(alpha: 0.2);

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
      builder: (context, lineCount) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: focused || hasError
                ? [
                    BoxShadow(
                      color: ringColor,
                      blurRadius: 0,
                      spreadRadius: kAppTextareaFocusRingSpread,
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 1,
                      offset: Offset(0, 1),
                    ),
                  ],
          ),
          child: SizedBox.expand(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: appMultilineInputDecoration(
                  context,
                  decoration: widget.decoration,
                  focused: focused,
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
                minLines: lineCount,
                maxLines: lineCount,
              ),
            ),
          ),
        );
      },
    );
  }
}
