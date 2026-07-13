// Adapted from flutter-shadcn-ui ShadTextareaFormField — App* naming, no shadcn_ui.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../form/app_form_field.dart';
import '../form/app_form_field_layout.dart';
import 'app_textarea.dart';

/// [AppFormField] wrapping [AppTextarea]; label / error / description come from
/// [AppFormFieldLayout], not from [InputDecoration.labelText].
class AppTextareaFormField extends StatelessWidget {
  const AppTextareaFormField({
    super.key,
    this.id,
    this.initialValue,
    this.controller,
    this.focusNode,
    this.label,
    this.error,
    this.description,
    this.validator,
    this.onChanged,
    this.onSaved,
    this.enabled = true,
    this.readOnly = false,
    this.autovalidateMode,
    this.restorationId,
    this.forceErrorText,
    this.onReset,
    this.toValueTransformer,
    this.fromValueTransformer,
    this.layoutStyle = AppFormFieldLayoutStyle.stacked,
    this.labelWidth = 140,
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
       );

  final String? id;
  final String? initialValue;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final Widget? label;
  final Widget Function(String error)? error;
  final Widget? description;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String?>? onChanged;
  final FormFieldSetter<String>? onSaved;
  final bool enabled;
  final bool readOnly;
  final AutovalidateMode? autovalidateMode;
  final String? restorationId;
  final String? forceErrorText;
  final VoidCallback? onReset;
  final AppFormToValueTransformer<String?>? toValueTransformer;
  final AppFormFromValueTransformer<String?>? fromValueTransformer;
  final AppFormFieldLayoutStyle layoutStyle;
  final double labelWidth;
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
  Widget build(BuildContext context) {
    return AppFormField<String>(
      id: id,
      initialValue: controller?.text ?? initialValue,
      focusNode: focusNode,
      label: label,
      error: error,
      description: description,
      validator: validator,
      onChanged: onChanged,
      onSaved: onSaved,
      enabled: enabled,
      readOnly: readOnly,
      autovalidateMode: autovalidateMode,
      restorationId: restorationId,
      forceErrorText: forceErrorText,
      onReset: onReset,
      toValueTransformer: toValueTransformer,
      fromValueTransformer: fromValueTransformer,
      layoutStyle: layoutStyle,
      labelWidth: labelWidth,
      builder: (state) {
        final baseDecoration = decoration ?? const InputDecoration();
        return AppTextarea(
          focusNode: state.focusNode,
          enabled: state.enabled,
          readOnly: readOnly,
          controller: controller,
          initialValue: controller == null
              ? (state.value ?? initialValue)
              : null,
          onChanged: state.didChange,
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
  }
}
