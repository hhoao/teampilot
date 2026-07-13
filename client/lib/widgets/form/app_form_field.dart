// Adapted from flutter-shadcn-ui ShadFormBuilderField — App* naming, no Shad theme.

import 'package:flutter/widgets.dart';

import 'app_form.dart';
import 'app_form_field_layout.dart';

/// Transforms a field value before it is stored in [AppFormState.value].
typedef AppFormToValueTransformer<T> = dynamic Function(T value);

/// Transforms a stored form value into the field's expected type.
typedef AppFormFromValueTransformer<T> = T Function(dynamic value);

/// Form field that registers with [AppForm] and lays out label / error / description.
///
/// Put a plain control in [builder] (e.g. [TextField]), not a nested [FormField].
class AppFormField<T> extends FormField<T> {
  AppFormField({
    super.key,
    required Widget Function(AppFormFieldState<AppFormField<T>, T> state)
    builder,
    super.onSaved,
    super.validator,
    super.initialValue,
    super.enabled,
    super.autovalidateMode,
    super.restorationId,
    super.forceErrorText,
    super.onReset,
    this.readOnly = false,
    this.id,
    this.focusNode,
    this.label,
    this.error,
    this.description,
    this.onChanged,
    this.toValueTransformer,
    this.fromValueTransformer,
  }) : super(
         builder: (fieldState) {
           final state = fieldState as AppFormFieldState<AppFormField<T>, T>;
           final hasError = state.hasError;
           final effectiveError = hasError
               ? error?.call(state.errorText!) ?? Text(state.errorText!)
               : null;

           return AppFormFieldLayout(
             label: label,
             error: effectiveError,
             description: description,
             child: builder(state),
           );
         },
       );

  /// Optional id used as the key in [AppFormState.value].
  final String? id;

  final FocusNode? focusNode;
  final Widget? label;
  final Widget Function(String error)? error;
  final Widget? description;
  final ValueChanged<T?>? onChanged;
  final AppFormToValueTransformer<T?>? toValueTransformer;
  final AppFormFromValueTransformer<T?>? fromValueTransformer;
  final bool readOnly;

  @override
  AppFormFieldState<AppFormField<T>, T> createState() =>
      AppFormFieldState<AppFormField<T>, T>();
}

/// State for [AppFormField], including focus and parent [AppForm] registration.
class AppFormFieldState<F extends AppFormField<T>, T>
    extends FormFieldState<T> {
  final String _internalId = UniqueKey().toString();
  FocusNode? _focusNode;
  AppFormState? _parentForm;
  String? _forceErrorText;

  FocusNode get focusNode => widget.focusNode ?? _focusNode!;

  String? get forceErrorText => widget.forceErrorText ?? _forceErrorText;

  @override
  String? get errorText => forceErrorText ?? super.errorText;

  @override
  bool get hasError => forceErrorText != null || super.hasError;

  void setError(String? error) {
    setState(() => _forceErrorText = error);
  }

  @override
  F get widget => super.widget as F;

  T? get initialValue {
    if (widget.initialValue != null) return widget.initialValue;
    if (widget.id == null || _parentForm == null) return null;
    final value = _parentForm!.getFieldValue(widget.id!);
    if (widget.fromValueTransformer != null) {
      return widget.fromValueTransformer!(value);
    }
    return value as T?;
  }

  bool get enabled => widget.enabled && (_parentForm?.enabled ?? true);

  String get effectiveId => widget.id ?? _internalId;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _focusNode = FocusNode(canRequestFocus: !widget.readOnly);
    }
    _parentForm = AppForm.maybeOf(context);
    _parentForm?.registerField(effectiveId, this);
  }

  @override
  void didUpdateWidget(covariant AppFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.id != oldWidget.id) {
      _parentForm?.unregisterField(oldWidget.id ?? _internalId, this);
      _parentForm?.registerField(effectiveId, this);
    }
    if (oldWidget.focusNode != null && widget.focusNode == null) {
      _focusNode ??= FocusNode(canRequestFocus: !widget.readOnly);
    }
    if (widget.readOnly != oldWidget.readOnly) {
      _focusNode?.canRequestFocus = !widget.readOnly;
    }
  }

  @override
  void didChange(T? value) {
    _parentForm?.setFieldValue<T>(effectiveId, value, notifyField: false);
    super.didChange(value);
    widget.onChanged?.call(value);
  }

  @override
  void reset() {
    super.reset();
    didChange(initialValue);
  }

  @override
  void dispose() {
    _parentForm?.unregisterField(effectiveId, this);
    _focusNode?.dispose();
    super.dispose();
  }

  void focus() {
    FocusScope.of(context).requestFocus(focusNode);
  }

  void ensureVisible() {
    Scrollable.ensureVisible(context);
  }

  @override
  void setValue(T? value, {bool populateForm = true}) {
    super.setValue(value);
    if (populateForm) {
      _parentForm?.setFieldValue<T>(effectiveId, value, notifyField: false);
    }
  }

  void registerToValueTransformer(Map<String, Function> map) {
    final fun = widget.toValueTransformer;
    if (fun != null) map[effectiveId] = fun;
  }

  void registerFromValueTransformer(Map<String, Function> map) {
    final fun = widget.fromValueTransformer;
    if (fun != null) map[effectiveId] = fun;
  }
}
