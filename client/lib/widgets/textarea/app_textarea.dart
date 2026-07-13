// Adapted from flutter-shadcn-ui Textarea; App* naming.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_control_theme.dart';
import 'app_textarea_extent.dart';
import 'app_textarea_shell.dart';

export 'app_textarea_extent.dart';

/// Multiline [InputDecoration] that clears the global single-line
/// [BoxConstraints.tightFor] track height and uses multiline padding.
InputDecoration appMultilineInputDecoration(
  BuildContext context, {
  InputDecoration? decoration,
}) {
  final control = AppControlTheme.fromContext(context);
  final base = decoration ?? const InputDecoration();
  return base.copyWith(
    // Empty constraints override theme `tightFor(height: control.height)`.
    constraints: const BoxConstraints(),
    contentPadding:
        base.contentPadding ??
        EdgeInsets.symmetric(
          horizontal: control.horizontalPadding,
          vertical: kAppTextareaVerticalPadding,
        ),
  );
}

/// Material [TextField] wrapped in [AppTextareaShell] with multiline-safe
/// decoration (clears global single-line outline height constraints).
///
/// [minHeight] / [maxHeight] are **outer** shell heights including padding
/// and outline borders. Prefer [appTextareaHeightForLines] at call sites.
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

  TextEditingController get _controller =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = TextEditingController(text: widget.initialValue);
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
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle =
        widget.style ?? Theme.of(context).textTheme.bodyMedium;

    return AppTextareaShell(
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      initialHeight: widget.initialHeight,
      resizable: widget.resizable,
      onHeightChanged: widget.onHeightChanged,
      resizeHandleBuilder: widget.resizeHandleBuilder,
      textStyle: textStyle,
      verticalChrome: appTextareaVerticalChrome(),
      builder: (context, lineCount) {
        return SizedBox.expand(
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            decoration: appMultilineInputDecoration(
              context,
              decoration: widget.decoration,
            ),
            onChanged: widget.onChanged,
            onEditingComplete: widget.onEditingComplete,
            onSubmitted: widget.onSubmitted,
            style: textStyle,
            strutStyle: widget.strutStyle,
            textAlign: widget.textAlign,
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
            cursorColor: widget.cursorColor,
            keyboardAppearance: widget.keyboardAppearance,
            scrollPadding: widget.scrollPadding,
            enableInteractiveSelection: widget.enableInteractiveSelection,
            selectionControls: widget.selectionControls,
            onTap: widget.onTap,
            onTapOutside: widget.onTapOutside,
            mouseCursor: widget.mouseCursor,
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
        );
      },
    );
  }
}
