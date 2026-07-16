import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_configuration.dart';
import '../../services/run/launch_config_l10n.dart';
import '../../services/run/launch_config_schema_fields.dart';
import 'package:shared_ui/shared_ui.dart';

/// Shared label column width for inline run-config form rows.
const double kLaunchConfigFormLabelWidth = 160;

/// Schema-driven editor for a single [LaunchConfiguration].
///
/// Must be a descendant of [TpForm]. Always shows Name above properties from
/// [schema]. Maps JSON-schema types to controls: string → text, string array →
/// whitespace-separated text, string map → `KEY=VALUE` lines, boolean →
/// [Checkbox], enum → [TpSelect].
///
/// Shell Script: shows `scriptPath` only when `execute == scriptFile`, and
/// `scriptText` only when `execute == scriptText`.
class LaunchConfigSchemaForm extends StatefulWidget {
  const LaunchConfigSchemaForm({
    required this.value,
    required this.onChanged,
    required this.schema,
    this.errors = const [],
    super.key,
  });

  final LaunchConfiguration value;
  final ValueChanged<LaunchConfiguration> onChanged;
  final Map<String, Object?> schema;
  final List<String> errors;

  @override
  State<LaunchConfigSchemaForm> createState() => _LaunchConfigSchemaFormState();
}

class _LaunchConfigSchemaFormState extends State<LaunchConfigSchemaForm> {
  late final TextEditingController _nameController;
  final Map<String, TextEditingController> _controllers = {};
  late List<LaunchConfigSchemaField> _fields;
  late LaunchConfiguration _working;

  @override
  void initState() {
    super.initState();
    _working = widget.value;
    _fields = launchConfigSchemaFields(widget.schema);
    _nameController = TextEditingController(text: _working.name);
    for (final field in _fields) {
      if (_isTextField(field.type)) {
        _controllers[field.key] = TextEditingController(
          text: _displayTextFor(_working, field),
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant LaunchConfigSchemaForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schema != widget.schema) {
      _fields = launchConfigSchemaFields(widget.schema);
      _working = widget.value;
      _rebuildControllers();
    } else if (widget.value != _working && widget.value != oldWidget.value) {
      // External replace (e.g. load another config) — not an echo of our emit.
      _working = widget.value;
      _syncControllersFromValue(_working);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isTextField(LaunchConfigSchemaFieldType type) =>
      type == LaunchConfigSchemaFieldType.string ||
      type == LaunchConfigSchemaFieldType.stringArray ||
      type == LaunchConfigSchemaFieldType.stringMap;

  void _rebuildControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    for (final field in _fields) {
      if (_isTextField(field.type)) {
        _controllers[field.key] = TextEditingController(
          text: _displayTextFor(_working, field),
        );
      }
    }
    if (_nameController.text != _working.name) {
      _nameController.value = TextEditingValue(
        text: _working.name,
        selection: TextSelection.collapsed(offset: _working.name.length),
      );
    }
  }

  void _syncControllersFromValue(LaunchConfiguration value) {
    if (_nameController.text != value.name) {
      _nameController.value = TextEditingValue(
        text: value.name,
        selection: TextSelection.collapsed(offset: value.name.length),
      );
    }
    for (final field in _fields) {
      if (!_isTextField(field.type)) continue;
      final controller = _controllers[field.key];
      if (controller == null) continue;
      final text = _displayTextFor(value, field);
      if (controller.text != text) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }
  }

  String _displayTextFor(
    LaunchConfiguration config,
    LaunchConfigSchemaField field,
  ) {
    switch (field.type) {
      case LaunchConfigSchemaFieldType.string:
      case LaunchConfigSchemaFieldType.enumValue:
        return _readString(config, field.key) ?? '';
      case LaunchConfigSchemaFieldType.stringArray:
        return stringifyLaunchArgs(_readStringList(config, field.key));
      case LaunchConfigSchemaFieldType.stringMap:
        return stringifyLaunchEnv(_readStringMap(config, field.key));
      case LaunchConfigSchemaFieldType.boolean:
      case LaunchConfigSchemaFieldType.unsupported:
        return '';
    }
  }

  String _executeMode() {
    final raw = _readString(_working, 'execute')?.trim();
    if (raw == null || raw.isEmpty) return 'scriptFile';
    return raw;
  }

  bool _shouldShowField(LaunchConfigSchemaField field) {
    if (field.key == 'scriptPath') return _executeMode() == 'scriptFile';
    if (field.key == 'scriptText') return _executeMode() == 'scriptText';
    return true;
  }

  void _emit(LaunchConfiguration next) {
    _working = next;
    widget.onChanged(next);
  }

  void _onNameChanged(String text) {
    _emit(_working.copyWith(name: text));
  }

  void _onFieldTextChanged(LaunchConfigSchemaField field, String text) {
    switch (field.type) {
      case LaunchConfigSchemaFieldType.string:
      case LaunchConfigSchemaFieldType.enumValue:
        _emit(_writeString(_working, field.key, text));
      case LaunchConfigSchemaFieldType.stringArray:
        _emit(
          _writeStringList(_working, field.key, parseLaunchArgsText(text)),
        );
      case LaunchConfigSchemaFieldType.stringMap:
        _emit(
          _writeStringMap(_working, field.key, parseLaunchEnvText(text)),
        );
      case LaunchConfigSchemaFieldType.boolean:
      case LaunchConfigSchemaFieldType.unsupported:
        break;
    }
  }

  void _onBoolChanged(String key, bool value) {
    _emit(_writeBool(_working, key, value));
  }

  void _onEnumChanged(String key, String value) {
    setState(() {
      _emit(_writeString(_working, key, value));
    });
  }

  InputDecoration _controlDecoration({required bool hasError}) {
    return InputDecoration(
      // Border reflects error; message is shown by TpFormFieldLayout / errors.
      errorText: hasError ? '' : null,
      errorStyle: const TextStyle(height: 0, fontSize: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.errors.isNotEmpty) ...[
          for (final error in widget.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                localizeLaunchConfigValidation(l10n, error),
                style: styles.smColored(cs.error),
              ),
            ),
        ],
        TpFormField<String>(
          id: 'name',
          initialValue: _working.name,
          label: Text(l10n.runConfigurationName),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: kLaunchConfigFormLabelWidth,
          builder: (state) {
            return TextField(
              key: const Key('launch-config-field-name'),
              controller: _nameController,
              focusNode: state.focusNode,
              textInputAction: TextInputAction.next,
              onChanged: (text) {
                state.didChange(text);
                _onNameChanged(text);
              },
              decoration: _controlDecoration(hasError: state.hasError),
            );
          },
        ),
        const SizedBox(height: 12),
        for (final field in _fields)
          if (field.type != LaunchConfigSchemaFieldType.unsupported &&
              _shouldShowField(field)) ...[
            _buildField(context, field, styles),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildField(
    BuildContext context,
    LaunchConfigSchemaField field,
    TpTextStyles styles,
  ) {
    final fieldKey = Key('launch-config-field-${field.key}');
    final label = Text(localizeLaunchConfigFieldLabel(context.l10n, field));
    switch (field.type) {
      case LaunchConfigSchemaFieldType.boolean:
        return TpFormField<bool>(
          id: field.key,
          initialValue: _readBool(_working, field.key) ?? false,
          label: label,
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: kLaunchConfigFormLabelWidth,
          builder: (state) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Checkbox(
                key: fieldKey,
                value: state.value ?? false,
                onChanged: (v) {
                  if (v == null) return;
                  state.didChange(v);
                  _onBoolChanged(field.key, v);
                },
              ),
            );
          },
        );
      case LaunchConfigSchemaFieldType.enumValue:
        final values = field.enumValues ?? const <String>[];
        final current = _readString(_working, field.key);
        final initial = values.contains(current)
            ? current
            : (values.isNotEmpty ? values.first : null);
        return TpFormField<String>(
          id: field.key,
          initialValue: initial ?? '',
          label: label,
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: kLaunchConfigFormLabelWidth,
          builder: (state) {
            return TpSelect<String>(
              key: fieldKey,
              items: values,
              initialItem: initial,
              searchable: false,
              decoration: TpSelectDecorations.themed(context),
              itemLabel: (value) =>
                  localizeLaunchConfigEnumValue(context.l10n, field.key, value),
              onChanged: (value) {
                if (value == null) return;
                state.didChange(value);
                _onEnumChanged(field.key, value);
              },
            );
          },
        );
      case LaunchConfigSchemaFieldType.stringMap:
        return TpFormField<String>(
          id: field.key,
          initialValue: _displayTextFor(_working, field),
          label: label,
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: kLaunchConfigFormLabelWidth,
          builder: (state) {
            final textStyle = field.monospace ? styles.mono : styles.md;
            return TpTextarea(
              key: fieldKey,
              controller: _controllers[field.key],
              focusNode: state.focusNode,
              style: field.monospace ? styles.mono : null,
              minHeight: tpTextareaHeightForLines(textStyle, lines: 3),
              maxHeight: tpTextareaHeightForLines(textStyle, lines: 8),
              onChanged: (t) {
                state.didChange(t);
                _onFieldTextChanged(field, t);
              },
              decoration: _controlDecoration(hasError: state.hasError).copyWith(
                alignLabelWithHint: true,
              ),
            );
          },
        );
      case LaunchConfigSchemaFieldType.string:
      case LaunchConfigSchemaFieldType.stringArray:
        return TpFormField<String>(
          id: field.key,
          initialValue: _displayTextFor(_working, field),
          label: label,
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: kLaunchConfigFormLabelWidth,
          builder: (state) {
            if (field.key == 'scriptText') {
              final textStyle = field.monospace ? styles.mono : styles.md;
              return TpTextarea(
                key: fieldKey,
                controller: _controllers[field.key],
                focusNode: state.focusNode,
                style: field.monospace ? styles.mono : null,
                minHeight: tpTextareaHeightForLines(textStyle, lines: 3),
                maxHeight: tpTextareaHeightForLines(textStyle, lines: 8),
                onChanged: (t) {
                  state.didChange(t);
                  _onFieldTextChanged(field, t);
                },
                decoration: _controlDecoration(hasError: state.hasError),
              );
            }
            return TextField(
              key: fieldKey,
              controller: _controllers[field.key],
              focusNode: state.focusNode,
              style: field.monospace ? styles.mono : null,
              textInputAction: TextInputAction.next,
              maxLines: 1,
              onChanged: (t) {
                state.didChange(t);
                _onFieldTextChanged(field, t);
              },
              decoration: _controlDecoration(hasError: state.hasError),
            );
          },
        );
      case LaunchConfigSchemaFieldType.unsupported:
        return const SizedBox.shrink();
    }
  }
}

String? _readString(LaunchConfiguration config, String key) {
  return switch (key) {
    'cwd' => config.cwd,
    'name' => config.name,
    'type' => config.type,
    'request' => config.request,
    'id' => config.id,
    _ => config.extras[key]?.toString(),
  };
}

List<String> _readStringList(LaunchConfiguration config, String key) {
  final raw = config.extras[key];
  if (raw is List) {
    return [for (final e in raw) e.toString()];
  }
  return const [];
}

Map<String, String> _readStringMap(LaunchConfiguration config, String key) {
  if (key == 'env') return config.env;
  final raw = config.extras[key];
  if (raw is Map) {
    return {
      for (final e in raw.entries) e.key.toString(): e.value?.toString() ?? '',
    };
  }
  return const {};
}

bool? _readBool(LaunchConfiguration config, String key) {
  final raw = config.extras[key];
  return raw is bool ? raw : null;
}

LaunchConfiguration _writeString(
  LaunchConfiguration config,
  String key,
  String text,
) {
  return switch (key) {
    'cwd' => config.copyWith(cwd: text),
    'name' => config.copyWith(name: text),
    'type' => config.copyWith(type: text),
    'request' => config.copyWith(request: text),
    'id' => config.copyWith(id: text),
    _ => config.copyWith(extras: {...config.extras, key: text}),
  };
}

LaunchConfiguration _writeStringList(
  LaunchConfiguration config,
  String key,
  List<String> values,
) {
  return config.copyWith(extras: {...config.extras, key: values});
}

LaunchConfiguration _writeStringMap(
  LaunchConfiguration config,
  String key,
  Map<String, String> values,
) {
  if (key == 'env') return config.copyWith(env: values);
  return config.copyWith(extras: {...config.extras, key: values});
}

LaunchConfiguration _writeBool(
  LaunchConfiguration config,
  String key,
  bool value,
) {
  return config.copyWith(extras: {...config.extras, key: value});
}
