// Adapted from flutter-shadcn-ui ShadForm — App* naming, no shadcn_ui dependency.

import 'package:flutter/widgets.dart';

import 'app_form_field.dart';
import 'app_form_map.dart';

/// Auto-validation policy for [AppForm] / [AppFormField].
enum AppAutovalidateMode {
  disabled,
  always,
  onUserInteraction,

  /// Disabled until the first [AppFormState.validate], then always.
  alwaysAfterFirstValidation,
}

/// Registered field states keyed by field id.
typedef AppFormFields =
    Map<
      String,
      AppFormFieldState<AppFormField<dynamic>, dynamic>
    >;

/// Form shell with field registry and aggregated [AppFormState.value].
class AppForm extends StatefulWidget {
  const AppForm({
    super.key,
    required this.child,
    this.onChanged,
    this.canPop,
    this.onPopInvokedWithResult,
    this.autovalidateMode = AppAutovalidateMode.alwaysAfterFirstValidation,
    this.initialValue = const {},
    this.enabled = true,
    this.clearValueOnUnregister = false,
    this.fieldIdSeparator = '.',
  });

  final VoidCallback? onChanged;
  final bool? canPop;
  final PopInvokedWithResultCallback<Object?>? onPopInvokedWithResult;
  final AppAutovalidateMode autovalidateMode;
  final Widget child;
  final Map<String, dynamic> initialValue;
  final bool enabled;
  final bool clearValueOnUnregister;

  /// Separator for nested keys in [AppFormState.value]. Pass `null` to keep flat keys.
  final String? fieldIdSeparator;

  @override
  State<AppForm> createState() => AppFormState();

  static AppFormState of(BuildContext context) {
    final state = maybeOf(context);
    assert(state != null, 'No AppFormState found in context');
    return state!;
  }

  static AppFormState? maybeOf(BuildContext context) {
    return (context
                .getElementForInheritedWidgetOfExactType<AppFormScope>()
                ?.widget
            as AppFormScope?)
        ?._formState;
  }
}

/// State for [AppForm].
class AppFormState extends State<AppForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final AppFormFields _fields = {};
  final Map<String, dynamic> _value = {};
  final Map<String, Function> _toValueTransformers = {};
  final Map<String, Function> _fromValueTransformers = {};
  late final ValueNotifier<AutovalidateMode> autovalidateMode;

  AppFormFields get fields => _fields;

  Map<String, dynamic> get initialValue => widget.initialValue;

  bool get enabled => widget.enabled;

  Map<String, dynamic> get rawValue {
    final base = Map<String, dynamic>.from(initialValue.deepCopy());
    final result = widget.fieldIdSeparator != null
        ? base.deepMerge(
            _value.toNestedMap(separator: widget.fieldIdSeparator!),
          )
        : base.deepMerge(_value);
    return Map<String, dynamic>.unmodifiable(result);
  }

  Map<String, dynamic> get value {
    final base = Map<String, dynamic>.from(initialValue.deepCopy());
    final transformedValue = _value.map(
      (key, value) => MapEntry(
        key,
        // ignore: avoid_dynamic_calls
        _toValueTransformers[key]?.call(value) ?? value,
      ),
    );
    final result = widget.fieldIdSeparator != null
        ? base.deepMerge(
            transformedValue.toNestedMap(separator: widget.fieldIdSeparator!),
          )
        : base.deepMerge(transformedValue);
    return Map<String, dynamic>.unmodifiable(result);
  }

  @override
  void initState() {
    super.initState();
    final mode = switch (widget.autovalidateMode) {
      AppAutovalidateMode.always => AutovalidateMode.always,
      AppAutovalidateMode.onUserInteraction =>
        AutovalidateMode.onUserInteraction,
      AppAutovalidateMode.alwaysAfterFirstValidation ||
      AppAutovalidateMode.disabled => AutovalidateMode.disabled,
    };
    autovalidateMode = ValueNotifier(mode);
  }

  @override
  void dispose() {
    autovalidateMode.dispose();
    super.dispose();
  }

  void registerField(
    String id,
    AppFormFieldState<AppFormField<dynamic>, dynamic> field,
  ) {
    _fields[id] = field;
    _value[id] = field.initialValue ?? getFieldValue(id);
    field
      ..registerToValueTransformer(_toValueTransformers)
      ..registerFromValueTransformer(_fromValueTransformers)
      ..setValue(_value[id]);
  }

  dynamic getFieldValue(String id) {
    if (widget.fieldIdSeparator == null) return rawValue[id];
    return rawValue.getByPath(id, separator: widget.fieldIdSeparator!);
  }

  void setFieldValue<T>(String id, T? value, {bool notifyField = true}) {
    _value[id] = value;
    if (notifyField) {
      // ignore: avoid_dynamic_calls
      _fields[id]?.didChange(_fromValueTransformers[id]?.call(value) ?? value);
    }
  }

  void setValue(
    Map<String, dynamic> value, {
    bool notifyFields = true,
    bool removeMissing = false,
    bool notifyRemovedFields = false,
  }) {
    if (removeMissing) {
      final keysToRemove = _value.keys
          .where((key) => !value.containsKey(key))
          .toList();
      for (final id in keysToRemove) {
        removeFieldValue(id, notifyField: notifyRemovedFields);
      }
    }
    for (final entry in value.entries) {
      final field = _fields[entry.key];
      final oldValue = _value[entry.key];
      _value[entry.key] = entry.value;
      if (notifyFields && field != null && oldValue != entry.value) {
        field.didChange(entry.value);
      }
    }
  }

  void setFieldError(String id, String? error) {
    final field = _fields[id];
    if (field == null) {
      throw FlutterError(
        'Field with id "$id" not found. '
        'Make sure the field is registered with the form.',
      );
    }
    field.setError(error);
  }

  void removeFieldValue(String id, {bool notifyField = false}) {
    _value.remove(id);
    if (notifyField) {
      _fields[id]?.didChange(null);
    }
  }

  void unregisterField(
    String id,
    AppFormFieldState<AppFormField<dynamic>, dynamic> field,
  ) {
    _fields.remove(id);
    _toValueTransformers.remove(id);
    _fromValueTransformers.remove(id);
    if (widget.clearValueOnUnregister) {
      removeFieldValue(id);
    }
  }

  bool validate({
    bool focusOnInvalid = true,
    bool autoScrollWhenFocusOnInvalid = false,
  }) {
    if (widget.autovalidateMode ==
        AppAutovalidateMode.alwaysAfterFirstValidation) {
      autovalidateMode.value = AutovalidateMode.always;
    }
    final hasError = !_formKey.currentState!.validate();
    if (hasError) {
      final wrongFields = _fields.values
          .where((element) => element.hasError)
          .toList();
      if (wrongFields.isNotEmpty) {
        if (focusOnInvalid) {
          wrongFields.first.focus();
        }
        if (autoScrollWhenFocusOnInvalid) {
          wrongFields.first.ensureVisible();
        }
      }
    }
    return !hasError;
  }

  bool saveAndValidate({
    bool focusOnInvalid = true,
    bool autoScrollWhenFocusOnInvalid = false,
  }) {
    save();
    return validate(
      focusOnInvalid: focusOnInvalid,
      autoScrollWhenFocusOnInvalid: autoScrollWhenFocusOnInvalid,
    );
  }

  void reset() {
    autovalidateMode.value = switch (widget.autovalidateMode) {
      AppAutovalidateMode.always => AutovalidateMode.always,
      AppAutovalidateMode.onUserInteraction =>
        AutovalidateMode.onUserInteraction,
      AppAutovalidateMode.alwaysAfterFirstValidation ||
      AppAutovalidateMode.disabled => AutovalidateMode.disabled,
    };
    _value.clear();
    _formKey.currentState?.reset();
  }

  void save() {
    _formKey.currentState!.save();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: autovalidateMode,
      builder: (context, mode, child) {
        return Form(
          key: _formKey,
          autovalidateMode: mode,
          onPopInvokedWithResult: widget.onPopInvokedWithResult,
          canPop: widget.canPop,
          onChanged: widget.onChanged,
          child: child!,
        );
      },
      child: AppFormScope(
        formState: this,
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Inherited access to [AppFormState].
class AppFormScope extends InheritedWidget {
  const AppFormScope({
    super.key,
    required super.child,
    required AppFormState formState,
  }) : _formState = formState;

  final AppFormState _formState;

  AppForm get form => _formState.widget;

  @override
  bool updateShouldNotify(AppFormScope oldWidget) =>
      oldWidget._formState != _formState;
}
