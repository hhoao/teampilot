// Adapted from flutter-shadcn-ui ShadTextareaFormField — App* naming, no shadcn_ui.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../form/app_form_field.dart';
import '../form/app_form_field_layout.dart';
import 'app_textarea.dart';

/// [AppFormField] wrapping [AppTextarea]; label / error / description come from
/// [AppFormFieldLayout], not from [InputDecoration.labelText].
///
/// Owns (or uses) a [TextEditingController] and keeps it in sync with the form
/// field value on [didChange] / [reset] / [AppFormState.setFieldValue].
class AppTextareaFormField extends AppFormField<String> {
  AppTextareaFormField({
    super.key,
    super.id,
    String? initialValue,
    this.controller,
    super.focusNode,
    super.label,
    super.error,
    super.description,
    super.validator,
    super.onChanged,
    super.onSaved,
    super.enabled,
    super.readOnly,
    super.autovalidateMode,
    super.restorationId,
    super.forceErrorText,
    super.onReset,
    super.toValueTransformer,
    super.fromValueTransformer,
    super.layoutStyle,
    super.labelWidth,
    this.decoration,
    this.style,
    this.strutStyle,
    this.textAlign = TextAlign.start,
    this.textDirection,
    this.showCursor,
    this.autofocus = false,
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
    this.scribbleEnabled = true,
    this.enableIMEPersonalizedLearning = true,
    this.contextMenuBuilder,
    this.spellCheckConfiguration,
    this.magnifierConfiguration,
    this.inputFormatters,
    this.onEditingComplete,
    this.onSubmitted,
    this.minHeight = 80,
    this.maxHeight = 500,
    this.initialHeight,
    this.resizable = true,
    this.onHeightChanged,
    this.resizeHandleBuilder,
  }) : assert(
         initialValue == null || controller == null,
         'Cannot provide both initialValue and controller',
       ),
       super(
         initialValue: controller != null ? controller.text : initialValue,
         builder: (state) {
           state as AppTextareaFormFieldState;
           final baseDecoration = decoration ?? const InputDecoration();
           return AppTextarea(
             focusNode: state.focusNode,
             enabled: state.enabled,
             readOnly: readOnly,
             controller: state.controller,
             onEditingComplete: onEditingComplete,
             onSubmitted: onSubmitted,
             decoration: baseDecoration.copyWith(
               // Border reflects error; message is shown by AppFormFieldLayout.
               errorText: state.hasError ? '' : null,
               errorStyle: const TextStyle(height: 0, fontSize: 0),
             ),
             style: style,
             strutStyle: strutStyle,
             textAlign: textAlign,
             textDirection: textDirection,
             showCursor: showCursor,
             autofocus: autofocus,
             maxLength: maxLength,
             maxLengthEnforcement: maxLengthEnforcement,
             cursorWidth: cursorWidth,
             cursorHeight: cursorHeight,
             cursorRadius: cursorRadius,
             cursorColor: cursorColor,
             keyboardAppearance: keyboardAppearance,
             scrollPadding: scrollPadding,
             enableInteractiveSelection: enableInteractiveSelection,
             selectionControls: selectionControls,
             onTap: onTap,
             onTapOutside: onTapOutside,
             mouseCursor: mouseCursor,
             scrollController: scrollController,
             scrollPhysics: scrollPhysics,
             clipBehavior: clipBehavior,
             restorationId: restorationId,
             scribbleEnabled: scribbleEnabled,
             enableIMEPersonalizedLearning: enableIMEPersonalizedLearning,
             contextMenuBuilder: contextMenuBuilder,
             spellCheckConfiguration: spellCheckConfiguration,
             magnifierConfiguration: magnifierConfiguration,
             inputFormatters: inputFormatters,
             minHeight: minHeight,
             maxHeight: maxHeight,
             initialHeight: initialHeight,
             resizable: resizable,
             onHeightChanged: onHeightChanged,
             resizeHandleBuilder: resizeHandleBuilder,
           );
         },
       );

  final TextEditingController? controller;
  final InputDecoration? decoration;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;
  final TextDirection? textDirection;
  final bool? showCursor;
  final bool autofocus;
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
  final bool scribbleEnabled;
  final bool enableIMEPersonalizedLearning;
  final EditableTextContextMenuBuilder? contextMenuBuilder;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final TextMagnifierConfiguration? magnifierConfiguration;
  final List<TextInputFormatter>? inputFormatters;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final double minHeight;
  final double maxHeight;
  final double? initialHeight;
  final bool resizable;
  final ValueChanged<double>? onHeightChanged;
  final WidgetBuilder? resizeHandleBuilder;

  @override
  AppFormFieldState<AppTextareaFormField, String> createState() =>
      AppTextareaFormFieldState();
}

class AppTextareaFormFieldState
    extends AppFormFieldState<AppTextareaFormField, String> {
  TextEditingController? _controller;

  TextEditingController get controller => widget.controller ?? _controller!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _controller = TextEditingController(text: value);
    }
    controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppTextareaFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _controller)?.removeListener(
        _onControllerChanged,
      );
      if (oldWidget.controller == null && widget.controller != null) {
        _controller?.dispose();
        _controller = null;
      } else if (oldWidget.controller != null && widget.controller == null) {
        _controller = TextEditingController(text: value);
      }
      controller.addListener(_onControllerChanged);
    }
  }

  @override
  void didChange(String? value) {
    super.didChange(value);
    if (controller.text != value) {
      controller.text = value ?? '';
    }
  }

  @override
  void reset() {
    super.reset();
    controller.text = initialValue ?? '';
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (controller.text != value) {
      didChange(controller.text);
    }
  }
}
