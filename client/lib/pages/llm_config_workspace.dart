import 'package:flutter/material.dart';

import '../utils/app_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/llm_config.dart';
import '../cubits/llm_config_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../theme/app_theme.dart';
import '../widgets/resizable_split_view.dart';

class LlmConfigWorkspace extends StatelessWidget {
  const LlmConfigWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LlmConfigCubit>();
    final l10n = context.l10n;
    final config = controller.state.config;
    return Column(
      key: AppKeys.llmConfigWorkspace,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorkspaceHeading(
          title: l10n.llmConfig,
          subtitle:
              '${controller.state.filePath} / ${config.providers.length} providers / ${config.models.length} models',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showValidationDialog(context, config),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(l10n.validate),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: AppKeys.saveLlmConfigButton,
                onPressed: controller.save,
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.save),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _ProvidersTabContent(controller: controller),
        ),
      ],
    );
  }
}

// --- Providers tab: split view ---

class _ProvidersTabContent extends StatefulWidget {
  const _ProvidersTabContent({required this.controller});

  final LlmConfigCubit controller;

  @override
  State<_ProvidersTabContent> createState() => _ProvidersTabContentState();
}

class _ProvidersTabContentState extends State<_ProvidersTabContent> {
  String? _modelsProviderName;

  LlmConfigCubit get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final config = _controller.state.config;
    final selectedName = _controller.state.effectiveProviderName;
    final selectedProvider = selectedName != null
        ? config.providers[selectedName]
        : null;

    final showModels = _modelsProviderName != null &&
        selectedProvider != null &&
        _modelsProviderName == selectedProvider.name;

    return ResizableSplitView(
      left: _ProviderListPanel(
        config: config,
        selectedName: selectedName,
        onSelect: (name) {
          _controller.selectProvider(name);
          setState(() => _modelsProviderName = null);
        },
        onAdd: () => _addProvider(context),
        onDelete: (name) => _deleteProvider(context, name),
      ),
      right: showModels
          ? _ProviderModelsView(
              config: config,
              provider: selectedProvider,
              controller: _controller,
              onBack: () => setState(() => _modelsProviderName = null),
            )
          : _ProviderDetailPanel(
              config: config,
              provider: selectedProvider,
              controller: _controller,
              onSave: (name, provider) {
                _controller.updateProvider(name, provider);
              },
              onDelete: (name) {
                _deleteProvider(context, name);
              },
              onShowModels: (name) =>
                  setState(() => _modelsProviderName = name),
            ),
    );
  }

  Future<void> _addProvider(BuildContext context) async {
    final l10n = context.l10n;
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.addProvider),
        content: TextField(
          key: AppKeys.providerNameDialogField,
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.providerName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text(l10n.add),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name != null &&
        name.isNotEmpty &&
        !_controller.state.config.providers.containsKey(name)) {
      _controller.addProvider(
        LlmProviderConfig(name: name, type: 'api', providerType: 'openai'),
      );
      _controller.selectProvider(name);
    }
  }

  Future<void> _deleteProvider(BuildContext context, String name) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteProvider),
        content: Text(l10n.deleteProviderConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _controller.deleteProvider(name);
    }
  }
}

// --- Provider list panel (left side of split) ---

class _ProviderListPanel extends StatefulWidget {
  const _ProviderListPanel({
    required this.config,
    required this.selectedName,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
  });

  final LlmConfig config;
  final String? selectedName;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<String> onDelete;

  @override
  State<_ProviderListPanel> createState() => _ProviderListPanelState();
}

class _ProviderListPanelState extends State<_ProviderListPanel> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final providers = widget.config.providers.values
        .where(
          (p) =>
              _searchQuery.isEmpty ||
              p.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    return Container(
        key: AppKeys.llmProviderList,
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.tabBarDivider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.providerList,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textBase,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: widget.onAdd,
                    child: Text(
                      '+ ${l10n.add}',
                      style: TextStyle(
                        color: colors.linkText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: TextField(
                key: AppKeys.llmProviderSearch,
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.filterProviders,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(left: 10, right: 10, bottom: 10),
                itemCount: providers.length,
                itemBuilder: (context, index) {
                  final provider = providers[index];
                  final isSelected = provider.name == widget.selectedName;
                  final modelCount = widget.config.models.values
                      .where((m) => m.provider == provider.name)
                      .length;
                  return _ProviderListRow(
                    provider: provider,
                    isSelected: isSelected,
                    modelCount: modelCount,
                    onTap: () => widget.onSelect(provider.name),
                    onDelete: () => widget.onDelete(provider.name),
                  );
                },
              ),
            ),
          ],
        ),
    );
  }
}

class _ProviderListRow extends StatelessWidget {
  const _ProviderListRow({
    required this.provider,
    required this.isSelected,
    required this.modelCount,
    required this.onTap,
    required this.onDelete,
  });

  final LlmProviderConfig provider;
  final bool isSelected;
  final int modelCount;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected
            ? colors.selectedBackground
            : colors.unselectedBackground,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? colors.selectedBorder
                    : colors.unselectedBorder,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: textBase,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          _TypeBadge(type: provider.type),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$modelCount models / proxy ${provider.proxy ? "on" : "off"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textBase.withValues(alpha: 0.48),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz, size: 16),
                  padding: EdgeInsets.zero,
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                  ],
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isAccount = type == 'account';
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: isAccount ? colors.typeBadgeAccountBg : colors.typeBadgeApiBg,
        border: Border.all(
          color: isAccount
              ? colors.typeBadgeAccountBorder
              : colors.typeBadgeApiBorder,
        ),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          color: isAccount
              ? colors.typeBadgeAccountText
              : colors.typeBadgeApiText,
        ),
      ),
    );
  }
}

// --- Provider detail panel (right side of split) ---

class _ProviderDetailPanel extends StatefulWidget {
  const _ProviderDetailPanel({
    required this.config,
    required this.provider,
    required this.controller,
    required this.onSave,
    required this.onDelete,
    required this.onShowModels,
  });

  final LlmConfig config;
  final LlmProviderConfig? provider;
  final LlmConfigCubit controller;
  final void Function(String name, LlmProviderConfig provider) onSave;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onShowModels;

  @override
  State<_ProviderDetailPanel> createState() => _ProviderDetailPanelState();
}

class _ProviderDetailPanelState extends State<_ProviderDetailPanel> {
  late String _type;
  late String _providerType;
  late final TextEditingController _baseUrlController;
  late String _apiKey;
  late bool _proxy;
  late final TextEditingController _proxyUrlController;
  late final TextEditingController _apiKeyController;
  late List<TextEditingController> _accountControllers;
  bool _apiKeyRevealed = false;
  bool _apiKeyReplaced = false;
  String? _providerName;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _proxyUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    _accountControllers = [];
    _syncFromProvider();
  }

  @override
  void didUpdateWidget(covariant _ProviderDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.provider?.name != _providerName) {
      _syncFromProvider();
    }
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

  void _syncFromProvider() {
    final provider = widget.provider;
    if (provider == null) {
      _providerName = null;
      return;
    }
    _providerName = provider.name;
    _type = provider.type;
    _providerType = provider.providerType;
    _baseUrlController.text = provider.baseUrl;
    _apiKey = provider.apiKey;
    _proxy = provider.proxy;
    _proxyUrlController.text = provider.proxyUrl;
    _apiKeyController.text = provider.apiKey.isEmpty
        ? ''
        : LlmConfig.maskedSecret;
    _apiKeyRevealed = false;
    _apiKeyReplaced = false;

    for (final c in _accountControllers) {
      c.dispose();
    }
    _accountControllers = provider.accounts
        .map((a) => TextEditingController(text: a))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final provider = widget.provider;
    if (provider == null) {
      return Container(
        key: AppKeys.llmProviderDetail,
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Center(
          child: Text(
            l10n.selectProvider,
            style: TextStyle(color: colors.emptyMessageText),
          ),
        ),
      );
    }

    final providerModels = widget.config.models.values
        .where((m) => m.provider == provider.name)
        .toList();

    return Container(
      key: AppKeys.llmProviderDetail,
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.tabBarDivider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            provider.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: textBase,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _TypeBadge(type: provider.type),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${provider.type.toUpperCase()} provider, used by ${providerModels.length} models',
                        style: TextStyle(
                          color: textBase.withValues(alpha: 0.48),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => widget.onShowModels(provider.name),
                  icon: const Icon(Icons.model_training_outlined, size: 16),
                  label: Text(l10n.models),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l10n.deleteProviderTooltip,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => widget.onDelete(provider.name),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    children: [
                      _SizedField(
                        child: _ReadOnlyField(
                          label: l10n.providerName,
                          value: provider.name,
                        ),
                      ),
                      _SizedField(
                        child: DropdownButtonFormField<String>(
                          value: _type,
                          decoration: InputDecoration(labelText: l10n.type),
                          items: [
                            DropdownMenuItem(
                              value: 'api',
                              child: Text(l10n.api),
                            ),
                            DropdownMenuItem(
                              value: 'account',
                              child: Text(l10n.account),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _type = value ?? 'api'),
                        ),
                      ),
                    ],
                  ),
                  if (_type == 'api') ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 10,
                      children: [
                        _SizedField(
                          child: TextField(
                            key: AppKeys.providerTypeField,
                            decoration: InputDecoration(
                              labelText: l10n.providerType,
                              hintText: l10n.providerTypeHint,
                            ),
                            controller:
                                TextEditingController(text: _providerType)
                                  ..selection = TextSelection.collapsed(
                                    offset: _providerType.length,
                                  ),
                            onChanged: (value) => _providerType = value,
                          ),
                        ),
                        _SizedField(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.proxy,
                                style: const TextStyle(fontSize: 12),
                              ),
                              Switch(
                                key: AppKeys.providerProxyToggle,
                                value: _proxy,
                                onChanged: (value) =>
                                    setState(() => _proxy = value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_proxy) ...[
                      const SizedBox(height: 10),
                      TextField(
                        key: AppKeys.proxyUrlField,
                        controller: _proxyUrlController,
                        decoration: InputDecoration(labelText: l10n.proxyUrl),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      key: AppKeys.baseUrlField,
                      controller: _baseUrlController,
                      decoration: InputDecoration(labelText: l10n.baseUrl),
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
                              labelText: l10n.apiKey,
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
                                          tooltip: _apiKeyRevealed
                                              ? l10n.hide
                                              : l10n.reveal,
                                          onPressed: () => setState(() {
                                            _apiKeyRevealed = !_apiKeyRevealed;
                                            if (_apiKeyRevealed &&
                                                !_apiKeyReplaced) {
                                              _apiKeyController.text = widget
                                                  .controller
                                                  .revealApiKey(provider.name);
                                            } else if (!_apiKeyRevealed) {
                                              _apiKeyController.text =
                                                  LlmConfig.maskedSecret;
                                            }
                                          }),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                            onChanged: (value) {
                              if (value != LlmConfig.maskedSecret) {
                                _apiKey = value;
                                _apiKeyReplaced = true;
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: AppKeys.replaceApiKeyButton,
                          tooltip: l10n.replaceKey,
                          onPressed: () {
                            _apiKeyController.clear();
                            _apiKey = '';
                            _apiKeyRevealed = true;
                            _apiKeyReplaced = true;
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
                                key: index == 0
                                    ? AppKeys.accountPathField
                                    : null,
                                controller: _accountControllers[index],
                                decoration: InputDecoration(
                                  labelText: l10n.accountCredentialPath,
                                ),
                              ),
                            ),
                            IconButton(
                              key: AppKeys.deleteAccountPathButton,
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: l10n.removePath,
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
                      label: Text(l10n.addAccountPath),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    spacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l10n.save),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          _syncFromProvider();
                        },
                        child: Text(l10n.cancel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (providerModels.isNotEmpty) ...[
                    _Section(
                      title: l10n.modelsUsingProviderTitle,
                      child: _ProviderModelsTable(
                        key: AppKeys.providerModelsTable,
                        models: providerModels,
                        providers: widget.config.providers,
                        onUpdate: (id, model) {
                          widget.controller.updateModel(id, model);
                        },
                        onDelete: (id) {
                          widget.controller.deleteModel(id);
                        },
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: textBase.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        l10n.noModelsUsingProvider,
                        style: TextStyle(
                          color: colors.emptyMessageText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    final provider = widget.provider;
    if (provider == null) return;
    widget.onSave(
      provider.name,
      provider.copyWith(
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

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textBase.withValues(alpha: 0.58),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.readOnlyFieldBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.readOnlyFieldBorder),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.readOnlyFieldText),
          ),
        ),
      ],
    );
  }
}

// --- Provider models mini table ---

class _ProviderModelsTable extends StatelessWidget {
  const _ProviderModelsTable({
    required this.models,
    required this.providers,
    required this.onUpdate,
    required this.onDelete,
    super.key,
  });

  final List<LlmModelConfig> models;
  final Map<String, LlmProviderConfig> providers;
  final void Function(String, LlmModelConfig) onUpdate;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final model in models)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    model.model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Switch(
                    key: AppKeys.modelEnabledToggle,
                    value: model.enabled,
                    onChanged: (value) {
                      onUpdate(model.id, model.copyWith(enabled: value));
                    },
                  ),
                ),
                _CompactIconButton(
                  tooltip: l10n.edit,
                  icon: Icons.edit_outlined,
                  onTap: () {
                    _editModel(context, model);
                  },
                ),
                _CompactIconButton(
                  tooltip: l10n.delete,
                  icon: Icons.delete_outline,
                  onTap: () {
                    onDelete(model.id);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _editModel(BuildContext context, LlmModelConfig model) async {
    final l10n = context.l10n;
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder: (context) => _ModelEditDialog(
        model: model,
        providers: providers,
        title: l10n.editModelTitle(model.name),
      ),
    );
    if (result != null) {
      onUpdate(model.id, result);
    }
  }
}

// --- Provider models view ---

class _ProviderModelsView extends StatelessWidget {
  const _ProviderModelsView({
    required this.config,
    required this.provider,
    required this.controller,
    required this.onBack,
  });

  final LlmConfig config;
  final LlmProviderConfig provider;
  final LlmConfigCubit controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final providerModels = config.models.values
        .where((m) => m.provider == provider.name)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.tabBarDivider)),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.back,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l10n.models} — ${provider.name}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: textBase,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${providerModels.length} ${l10n.models.toLowerCase()}',
                        style: TextStyle(
                          color: textBase.withValues(alpha: 0.48),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => _addModel(context, provider.name),
                  child: Text(
                    '+ ${l10n.add}',
                    style: TextStyle(
                      color: colors.linkText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: providerModels.isEmpty
                ? Center(
                    child: Text(
                      l10n.noModelsConfigured,
                      style: TextStyle(color: colors.emptyMessageText),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: providerModels.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final model = providerModels[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: textBase.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    model.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: textBase,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    model.model,
                                    style: TextStyle(
                                      color: textBase.withValues(alpha: 0.54),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: model.enabled,
                              onChanged: (value) {
                                controller.updateModel(
                                  model.id,
                                  model.copyWith(enabled: value),
                                );
                              },
                            ),
                            IconButton(
                              tooltip: l10n.edit,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              onPressed: () => _editModel(context, model),
                            ),
                            IconButton(
                              tooltip: l10n.delete,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              onPressed: () => controller.deleteModel(model.id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addModel(BuildContext context, String providerName) async {
    final l10n = context.l10n;
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder: (context) => _ModelEditDialog(
        providers: config.providers,
        defaultProvider: providerName,
        title: l10n.addModel,
      ),
    );
    if (result != null) {
      controller.addModel(result);
    }
  }

  Future<void> _editModel(BuildContext context, LlmModelConfig model) async {
    final l10n = context.l10n;
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder: (context) => _ModelEditDialog(
        model: model,
        providers: config.providers,
        title: l10n.editModelTitle(model.name),
      ),
    );
    if (result != null) {
      controller.updateModel(model.id, result);
    }
  }
}

// --- Validation dialog ---

Future<void> _showValidationDialog(BuildContext context, LlmConfig config) {
  final l10n = context.l10n;
  final messages = config.validationMessages;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.validation),
      content: SizedBox(
        width: 400,
        child: messages.isEmpty
            ? Text(l10n.allChecksPassed)
            : ListView.separated(
                shrinkWrap: true,
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => Text(
                  '${index + 1}. ${messages[index]}',
                  style: const TextStyle(height: 1.35),
                ),
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );
}

// --- Model edit dialog ---

class _ModelEditDialog extends StatefulWidget {
  const _ModelEditDialog({
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
  State<_ModelEditDialog> createState() => _ModelEditDialogState();
}

class _ModelEditDialogState extends State<_ModelEditDialog> {
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
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: AppKeys.modelNameDialogField,
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.modelName),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: AppKeys.modelProviderField,
              value: widget.providers.containsKey(_provider) ? _provider : null,
              decoration: InputDecoration(labelText: l10n.provider),
              items: [
                for (final p in widget.providers.values)
                  DropdownMenuItem(value: p.name, child: Text(p.name)),
              ],
              onChanged: (value) => setState(() => _provider = value ?? ''),
            ),
            const SizedBox(height: 14),
            TextField(
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
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
    );
  }
}

// --- Shared helpers (private to this file) ---

class _WorkspaceHeading extends StatelessWidget {
  const _WorkspaceHeading({required this.title, required this.subtitle, this.trailing});

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: textBase,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(color: textBase.withValues(alpha: 0.64)),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w800, color: textBase),
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
    return SizedBox(width: 200, child: child);
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}
