import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/llm_config.dart';
import '../../utils/ui/app_keys.dart';

class LlmModelEditDialog extends StatefulWidget {
  const LlmModelEditDialog({
    super.key,
    required this.providers,
    this.model,
    this.defaultProvider = '',
    required this.title,
  });

  final Map<String, LlmProviderConfig> providers;
  final LlmModelConfig? model;
  final String defaultProvider;
  final String title;

  @override
  State<LlmModelEditDialog> createState() => LlmModelEditDialogState();
}

class LlmModelEditDialogState extends State<LlmModelEditDialog> {
  final _formKey = GlobalKey<TpFormState>();
  late final TextEditingController _nameController;
  late String _provider;
  late final TextEditingController _modelController;
  late bool _enabled;

  bool get isEditing => widget.model != null;

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    _nameController = TextEditingController(text: model?.name ?? '');
    _provider = model?.provider ?? widget.defaultProvider;
    _modelController = TextEditingController(text: model?.model ?? '');
    _enabled = model?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final providerNames = widget.providers.keys.toList()..sort();
    final deco = TpSelectDecorations.themed(
      context,
      borderRadius: 8,
      suffixIconSize: context.tpIconSizes.md,
      expandedShadowBlurRadius: 18,
      expandedShadowAlphaDark: 0.45,
    );
    final initialProvider = widget.providers.containsKey(_provider)
        ? _provider
        : null;

    return TpDialog(
      maxWidth: 400,
      child: TpForm(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: widget.title),
            const SizedBox(height: 16),
            TpInputFormField(
              key: AppKeys.modelNameDialogField,
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.modelName),
              validator: (value) =>
                  (value == null || value.trim().isEmpty)
                      ? l10n.formFieldRequired
                      : null,
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.provider,
                  style: TpTextStyles.of(context).mdSemibold,
                ),
                const SizedBox(height: 8),
                TpSelectFormField<String>(
                  key: AppKeys.modelProviderField,
                  id: 'provider',
                  items: providerNames,
                  initialValue: initialProvider,
                  hintText: l10n.provider,
                  decoration: deco,
                  validator: (value) =>
                      (value == null || value.isEmpty)
                          ? l10n.formFieldRequired
                          : null,
                  onChanged: (value) => setState(() => _provider = value ?? ''),
                  itemLabel: (value) => value,
                ),
              ],
            ),
            const SizedBox(height: 14),
            TpInputFormField(
              key: AppKeys.modelModelIdField,
              controller: _modelController,
              decoration: InputDecoration(labelText: l10n.modelId),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              key: AppKeys.modelEnabledToggle,
              title: Text(l10n.enabled),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    final name = _nameController.text.trim();
                    Navigator.pop(
                      context,
                      LlmModelConfig(
                        id: isEditing ? widget.model!.id : name,
                        name: name,
                        provider: _provider,
                        model: _modelController.text.trim(),
                        enabled: _enabled,
                      ),
                    );
                  },
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
