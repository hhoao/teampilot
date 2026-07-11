import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/run/launch_configuration.dart';
import '../../services/run/launch_config_schema_fields.dart';
import '../../theme/app_text_styles.dart';

/// Schema-driven editor for a single [LaunchConfiguration].
///
/// Always shows Name above properties from [schema]. Maps JSON-schema types to
/// controls: string → text, string array → whitespace-separated text, string map
/// → `KEY=VALUE` lines, boolean → [Switch].
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

  @override
  void initState() {
    super.initState();
    _fields = launchConfigSchemaFields(widget.schema);
    _nameController = TextEditingController(text: widget.value.name);
    for (final field in _fields) {
      if (_isTextField(field.type)) {
        _controllers[field.key] = TextEditingController(
          text: _displayTextFor(widget.value, field),
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant LaunchConfigSchemaForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schema != widget.schema) {
      _fields = launchConfigSchemaFields(widget.schema);
      _rebuildControllers();
    } else if (oldWidget.value != widget.value) {
      _syncControllersFromValue(widget.value);
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
          text: _displayTextFor(widget.value, field),
        );
      }
    }
    if (_nameController.text != widget.value.name) {
      _nameController.text = widget.value.name;
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

  void _emit(LaunchConfiguration next) => widget.onChanged(next);

  void _onNameChanged(String text) {
    _emit(widget.value.copyWith(name: text));
  }

  void _onFieldTextChanged(LaunchConfigSchemaField field, String text) {
    switch (field.type) {
      case LaunchConfigSchemaFieldType.string:
        _emit(_writeString(widget.value, field.key, text));
      case LaunchConfigSchemaFieldType.stringArray:
        _emit(
          _writeStringList(widget.value, field.key, parseLaunchArgsText(text)),
        );
      case LaunchConfigSchemaFieldType.stringMap:
        _emit(
          _writeStringMap(widget.value, field.key, parseLaunchEnvText(text)),
        );
      case LaunchConfigSchemaFieldType.boolean:
      case LaunchConfigSchemaFieldType.unsupported:
        break;
    }
  }

  void _onBoolChanged(String key, bool value) {
    _emit(_writeBool(widget.value, key, value));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.errors.isNotEmpty) ...[
          for (final error in widget.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error,
                style: styles.smColored(cs.error),
              ),
            ),
        ],
        TextField(
          key: const Key('launch-config-field-name'),
          controller: _nameController,
          decoration: InputDecoration(labelText: l10n.name),
          textInputAction: TextInputAction.next,
          onChanged: _onNameChanged,
        ),
        const SizedBox(height: 12),
        for (final field in _fields)
          if (field.type != LaunchConfigSchemaFieldType.unsupported) ...[
            _buildField(context, field, styles),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildField(
    BuildContext context,
    LaunchConfigSchemaField field,
    AppTextStyles styles,
  ) {
    final fieldKey = Key('launch-config-field-${field.key}');
    switch (field.type) {
      case LaunchConfigSchemaFieldType.boolean:
        return _SwitchRow(
          title: field.label,
          value: _readBool(widget.value, field.key) ?? false,
          switchKey: fieldKey,
          onChanged: (v) => _onBoolChanged(field.key, v),
        );
      case LaunchConfigSchemaFieldType.stringMap:
        return TextField(
          key: fieldKey,
          controller: _controllers[field.key],
          decoration: InputDecoration(
            labelText: field.label,
            alignLabelWithHint: true,
          ),
          style: field.monospace ? styles.mono : null,
          minLines: 3,
          maxLines: 8,
          onChanged: (t) => _onFieldTextChanged(field, t),
        );
      case LaunchConfigSchemaFieldType.string:
      case LaunchConfigSchemaFieldType.stringArray:
        return TextField(
          key: fieldKey,
          controller: _controllers[field.key],
          decoration: InputDecoration(labelText: field.label),
          style: field.monospace ? styles.mono : null,
          textInputAction: TextInputAction.next,
          onChanged: (t) => _onFieldTextChanged(field, t),
        );
      case LaunchConfigSchemaFieldType.unsupported:
        return const SizedBox.shrink();
    }
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.switchKey,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final Key switchKey;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: styles.mdMedium,
          ),
        ),
        Switch(key: switchKey, value: value, onChanged: onChanged),
      ],
    );
  }
}

String? _readString(LaunchConfiguration config, String key) {
  return switch (key) {
    'command' => config.command,
    'cwd' => config.cwd,
    'name' => config.name,
    'type' => config.type,
    'request' => config.request,
    'id' => config.id,
    _ => config.extras[key]?.toString(),
  };
}

List<String> _readStringList(LaunchConfiguration config, String key) {
  if (key == 'args') return config.args;
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
  if (key == 'shell') return config.shell;
  final raw = config.extras[key];
  return raw is bool ? raw : null;
}

LaunchConfiguration _writeString(
  LaunchConfiguration config,
  String key,
  String text,
) {
  return switch (key) {
    'command' => config.copyWith(command: text),
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
  if (key == 'args') return config.copyWith(args: values);
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
  if (key == 'shell') return config.copyWith(shell: value);
  return config.copyWith(extras: {...config.extras, key: value});
}
