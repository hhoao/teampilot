import 'package:flutter/material.dart';

import '../app_keys.dart';
import '../llm_config.dart';
import '../llm_config_controller.dart';

class LlmConfigWorkspace extends StatefulWidget {
  const LlmConfigWorkspace({required this.controller, super.key});

  final LlmConfigController controller;

  @override
  State<LlmConfigWorkspace> createState() => _LlmConfigWorkspaceState();
}

class _LlmConfigWorkspaceState extends State<LlmConfigWorkspace> {
  String? _editingProviderName;
  String? _editingModelId;

  LlmConfigController get controller => widget.controller;

  void _startEditProvider(String name) =>
      setState(() => _editingProviderName = name);
  void _cancelEditProvider() => setState(() => _editingProviderName = null);
  void _startEditModel(String id) => setState(() => _editingModelId = id);
  void _cancelEditModel() => setState(() => _editingModelId = null);

  @override
  Widget build(BuildContext context) {
    final config = controller.config;
    return DefaultTabController(
      length: 3,
      child: Column(
        key: AppKeys.llmConfigWorkspace,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkspaceHeading(
            title: 'LLM Config',
            subtitle:
                '${controller.filePath} / ${config.providers.length} providers / ${config.models.length} models',
          ),
          const SizedBox(height: 10),
          _LlmValidationSummary(config: config),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: TabBar(
                  tabs: [
                    Tab(key: AppKeys.llmProvidersTab, text: 'Providers'),
                    Tab(key: AppKeys.llmModelsTab, text: 'Models'),
                    Tab(key: AppKeys.llmRawJsonTab, text: 'Raw JSON'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: AppKeys.saveLlmConfigButton,
                onPressed: controller.save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              children: [
                _ProvidersTab(
                  config: config,
                  editingName: _editingProviderName,
                  onStartEdit: _startEditProvider,
                  onCancelEdit: _cancelEditProvider,
                  onAdd: _addProvider,
                  onUpdate: (name, provider) {
                    controller.updateProvider(name, provider);
                    _cancelEditProvider();
                  },
                  onDelete: _deleteProvider,
                ),
                _ModelsTab(
                  config: config,
                  editingId: _editingModelId,
                  onStartEdit: _startEditModel,
                  onCancelEdit: _cancelEditModel,
                  onAdd: _addModel,
                  onUpdate: (id, model) {
                    controller.updateModel(id, model);
                    _cancelEditModel();
                  },
                  onDelete: _deleteModel,
                ),
                _RawJsonTab(config: config),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addProvider() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Provider'),
        content: TextField(
          key: AppKeys.providerNameDialogField,
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Provider name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name != null &&
        name.isNotEmpty &&
        !controller.config.providers.containsKey(name)) {
      controller.addProvider(
        LlmProviderConfig(name: name, type: 'api', providerType: 'openai'),
      );
      setState(() => _editingProviderName = name);
    }
  }

  Future<void> _deleteProvider(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Provider'),
        content: Text('Delete provider $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.deleteProvider(name);
      if (_editingProviderName == name) {
        _editingProviderName = null;
      }
    }
  }

  Future<void> _addModel() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Model'),
        content: TextField(
          key: AppKeys.modelNameDialogField,
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Model alias/name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name != null &&
        name.isNotEmpty &&
        !controller.config.models.containsKey(name)) {
      final defaultProvider =
          controller.config.providers.keys.firstOrNull ?? '';
      controller.addModel(
        LlmModelConfig(
          id: name,
          name: name,
          provider: defaultProvider,
          model: name,
          enabled: true,
        ),
      );
      setState(() => _editingModelId = name);
    }
  }

  Future<void> _deleteModel(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text('Delete model $id?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.deleteModel(id);
      if (_editingModelId == id) {
        _editingModelId = null;
      }
    }
  }
}

// --- Provider Edit Form ---

class _ProviderEditForm extends StatefulWidget {
  const _ProviderEditForm({
    required this.provider,
    required this.config,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  final LlmProviderConfig provider;
  final LlmConfig config;
  final ValueChanged<LlmProviderConfig> onSave;
  final VoidCallback onCancel;

  @override
  State<_ProviderEditForm> createState() => _ProviderEditFormState();
}

class _ProviderEditFormState extends State<_ProviderEditForm> {
  late String _type;
  late String _providerType;
  late final TextEditingController _baseUrlController;
  late String _apiKey;
  late bool _proxy;
  late final TextEditingController _proxyUrlController;
  late final TextEditingController _apiKeyController;
  late final List<TextEditingController> _accountControllers;
  bool _apiKeyRevealed = false;

  @override
  void initState() {
    super.initState();
    _type = widget.provider.type;
    _providerType = widget.provider.providerType;
    _baseUrlController = TextEditingController(text: widget.provider.baseUrl);
    _apiKey = widget.provider.apiKey;
    _proxy = widget.provider.proxy;
    _proxyUrlController = TextEditingController(text: widget.provider.proxyUrl);
    _apiKeyController = TextEditingController(
      text: widget.provider.apiKey.isEmpty ? '' : LlmConfig.maskedSecret,
    );
    _accountControllers = widget.provider.accounts
        .map((a) => TextEditingController(text: a))
        .toList();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _proxyUrlController.dispose();
    _apiKeyController.dispose();
    for (final c in _accountControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Edit ${widget.provider.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              _SizedField(
                child: DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'api', child: Text('api')),
                    DropdownMenuItem(value: 'account', child: Text('account')),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? 'api'),
                ),
              ),
              if (_type == 'api')
                _SizedField(
                  child: TextField(
                    key: AppKeys.providerTypeField,
                    controller: TextEditingController(text: _providerType)
                      ..selection = TextSelection.collapsed(
                        offset: _providerType.length,
                      ),
                    decoration: const InputDecoration(
                      labelText: 'Provider type',
                      hintText: 'openai, claude, or custom',
                    ),
                    onChanged: (value) => _providerType = value,
                  ),
                ),
            ],
          ),
          if (_type == 'api') ...[
            const SizedBox(height: 10),
            TextField(
              key: AppKeys.baseUrlField,
              controller: _baseUrlController,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: AppKeys.apiKeyField,
                    controller: _apiKeyController,
                    obscureText: !_apiKeyRevealed && _apiKey.isNotEmpty,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      suffixIcon: _apiKey.isNotEmpty
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: AppKeys.revealApiKeyButton,
                                  icon: Icon(
                                    _apiKeyRevealed
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  tooltip:
                                      _apiKeyRevealed ? 'Hide' : 'Reveal',
                                  onPressed: () => setState(
                                    () => _apiKeyRevealed = !_apiKeyRevealed,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      if (value != LlmConfig.maskedSecret) {
                        _apiKey = value;
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: AppKeys.replaceApiKeyButton,
                  tooltip: 'Replace key',
                  onPressed: () {
                    _apiKeyController.clear();
                    _apiKey = '';
                    _apiKeyRevealed = true;
                  },
                  icon: const Icon(Icons.key_outlined),
                ),
              ],
            ),
          ],
          if (_type == 'account') ...[
            const SizedBox(height: 10),
            ...List.generate(_accountControllers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: index == 0 ? AppKeys.accountPathField : null,
                        controller: _accountControllers[index],
                        decoration: const InputDecoration(
                          labelText: 'Account credential path',
                        ),
                      ),
                    ),
                    IconButton(
                      key: AppKeys.deleteAccountPathButton,
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove path',
                      onPressed: () => setState(() {
                        _accountControllers[index].dispose();
                        _accountControllers.removeAt(index);
                      }),
                    ),
                  ],
                ),
              );
            }),
            OutlinedButton.icon(
              key: AppKeys.addAccountPathButton,
              onPressed: () => setState(
                () => _accountControllers.add(TextEditingController()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Add account path'),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            spacing: 14,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Proxy', style: TextStyle(fontSize: 12)),
                  Switch(
                    key: AppKeys.providerProxyToggle,
                    value: _proxy,
                    onChanged: (value) => setState(() => _proxy = value),
                  ),
                ],
              ),
              if (_proxy)
                _SizedField(
                  child: TextField(
                    key: AppKeys.proxyUrlField,
                    controller: _proxyUrlController,
                    decoration: const InputDecoration(labelText: 'Proxy URL'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
              OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save() {
    widget.onSave(
      widget.provider.copyWith(
        type: _type,
        providerType: _type == 'api' ? _providerType : '',
        baseUrl: _type == 'api' ? _baseUrlController.text : '',
        apiKey: _type == 'api' ? _apiKey : '',
        proxy: _proxy,
        proxyUrl: _proxy ? _proxyUrlController.text : '',
        accounts: _type == 'account'
                ? _accountControllers.map((c) => c.text).toList()
                : const [],
      ),
    );
  }
}

// --- Model Edit Form ---

class _ModelEditForm extends StatefulWidget {
  const _ModelEditForm({
    required this.model,
    required this.config,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  final LlmModelConfig model;
  final LlmConfig config;
  final ValueChanged<LlmModelConfig> onSave;
  final VoidCallback onCancel;

  @override
  State<_ModelEditForm> createState() => _ModelEditFormState();
}

class _ModelEditFormState extends State<_ModelEditForm> {
  late final TextEditingController _nameController;
  late String _provider;
  late final TextEditingController _modelController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.model.name);
    _provider = widget.model.provider;
    _modelController = TextEditingController(text: widget.model.model);
    _enabled = widget.model.enabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Edit ${widget.model.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              _SizedField(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              _SizedField(
                child: DropdownButtonFormField<String>(
                  key: AppKeys.modelProviderField,
                  value: widget.config.providers.containsKey(_provider)
                      ? _provider
                      : null,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: [
                    for (final p in widget.config.providers.values)
                      DropdownMenuItem(value: p.name, child: Text(p.name)),
                  ],
                  onChanged: (value) =>
                      setState(() => _provider = value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: AppKeys.modelModelIdField,
            controller: _modelController,
            decoration: const InputDecoration(labelText: 'Model ID'),
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            key: AppKeys.modelEnabledToggle,
            title: const Text('Enabled'),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
              OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save() {
    widget.onSave(
      widget.model.copyWith(
        name: _nameController.text,
        provider: _provider,
        model: _modelController.text,
        enabled: _enabled,
      ),
    );
  }
}

// --- Shared helpers (private to this file) ---

class _WorkspaceHeading extends StatelessWidget {
  const _WorkspaceHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.64)),
        ),
      ],
    );
  }
}

class _LlmValidationSummary extends StatelessWidget {
  const _LlmValidationSummary({required this.config});

  final LlmConfig config;

  @override
  Widget build(BuildContext context) {
    final messages = config.validationMessages;
    return Container(
      key: AppKeys.llmValidationSummary,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x2B94A3B8)),
      ),
      child: messages.isEmpty
          ? const Text('No validation warnings.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${messages.length} validation warnings'),
                const SizedBox(height: 6),
                for (final message in messages)
                  Text(
                    message,
                    style: const TextStyle(color: Color(0xFFFFD166)),
                  ),
              ],
            ),
    );
  }
}

class _ProvidersTab extends StatelessWidget {
  const _ProvidersTab({
    required this.config,
    required this.editingName,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
  });

  final LlmConfig config;
  final String? editingName;
  final ValueChanged<String> onStartEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onAdd;
  final void Function(String, LlmProviderConfig) onUpdate;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            key: AppKeys.addProviderButton,
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Provider'),
          ),
        ),
        for (final provider in config.providers.values)
          if (provider.name == editingName)
            _ProviderEditForm(
              key: AppKeys.providerEditForm,
              provider: provider,
              config: config,
              onSave: (updated) => onUpdate(provider.name, updated),
              onCancel: onCancelEdit,
            )
          else
            _Section(
              title: provider.name,
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    key: AppKeys.editProviderButton(provider.name),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    onPressed: () => onStartEdit(provider.name),
                  ),
                  IconButton(
                    key: AppKeys.deleteProviderButton(provider.name),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete',
                    onPressed: () => onDelete(provider.name),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _Info(label: 'Type', value: provider.type),
                  if (provider.providerType.isNotEmpty)
                    _Info(label: 'Provider type', value: provider.providerType),
                  if (provider.baseUrl.isNotEmpty)
                    _Info(label: 'Base URL', value: provider.baseUrl),
                  if (provider.accounts.isNotEmpty)
                    _Info(
                      label: 'Accounts',
                      value: provider.accounts.join(', '),
                    ),
                  _Info(label: 'Proxy', value: provider.proxy ? 'on' : 'off'),
                  _Info(
                    label: 'API key',
                    value: provider.apiKey.isEmpty
                        ? 'empty'
                        : LlmConfig.maskedSecret,
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _ModelsTab extends StatelessWidget {
  const _ModelsTab({
    required this.config,
    required this.editingId,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
  });

  final LlmConfig config;
  final String? editingId;
  final ValueChanged<String> onStartEdit;
  final VoidCallback onCancelEdit;
  final VoidCallback onAdd;
  final void Function(String, LlmModelConfig) onUpdate;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            key: AppKeys.addModelButton,
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Model'),
          ),
        ),
        for (final model in config.models.values)
          if (model.id == editingId)
            _ModelEditForm(
              key: AppKeys.modelEditForm,
              model: model,
              config: config,
              onSave: (updated) => onUpdate(model.id, updated),
              onCancel: onCancelEdit,
            )
          else
            _Section(
              title: model.name,
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    key: AppKeys.editModelButton(model.id),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit',
                    onPressed: () => onStartEdit(model.id),
                  ),
                  IconButton(
                    key: AppKeys.deleteModelButton(model.id),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete',
                    onPressed: () => onDelete(model.id),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _Info(label: 'Provider', value: model.provider),
                  _Info(label: 'Actual model', value: model.model),
                  _Info(label: 'Enabled', value: model.enabled ? 'yes' : 'no'),
                ],
              ),
            ),
      ],
    );
  }
}

class _RawJsonTab extends StatelessWidget {
  const _RawJsonTab({required this.config});

  final LlmConfig config;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SelectableText(
        key: AppKeys.llmRawJsonPreview,
        config.toMaskedJsonString(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.54),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 3),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x2B94A3B8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SizedField extends StatelessWidget {
  const _SizedField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 360, child: child);
  }
}
