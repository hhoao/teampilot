import 'package:flutter/material.dart';

import '../utils/app_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/llm_config.dart';
import '../controllers/llm_config_controller.dart';
import '../theme/app_theme.dart';

class LlmConfigWorkspace extends StatefulWidget {
  const LlmConfigWorkspace({required this.controller, super.key});

  final LlmConfigController controller;

  @override
  State<LlmConfigWorkspace> createState() => _LlmConfigWorkspaceState();
}

class _LlmConfigWorkspaceState extends State<LlmConfigWorkspace> {
  LlmConfigController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = controller.config;
    return DefaultTabController(
      length: 3,
      child: Column(
        key: AppKeys.llmConfigWorkspace,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkspaceHeading(
            title: l10n.llmConfig,
            subtitle:
                '${controller.filePath} / ${config.providers.length} providers / ${config.models.length} models',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TabBar(
                  tabs: [
                    Tab(key: AppKeys.llmProvidersTab, text: l10n.providersTab),
                    Tab(key: AppKeys.llmModelsTab, text: l10n.modelsTab),
                    Tab(key: AppKeys.llmRawJsonTab, text: l10n.rawJsonTab),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: AppKeys.saveLlmConfigButton,
                onPressed: controller.save,
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.save),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: TabBarView(
                    children: [
                      _ProvidersTabContent(controller: controller),
                      _ModelsTabContent(controller: controller),
                      _RawJsonTabContent(controller: controller),
                    ],
                  ),
                ),
                SizedBox(
                  width: 340,
                  child: _LlmSidePanel(config: config),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Providers tab: split view ---

class _ProvidersTabContent extends StatelessWidget {
  const _ProvidersTabContent({required this.controller});

  final LlmConfigController controller;

  @override
  Widget build(BuildContext context) {
    final config = controller.config;
    final selectedName = controller.selectedProviderName;
    final selectedProvider =
        selectedName != null ? config.providers[selectedName] : null;

    return Row(
      children: [
        _ProviderListPanel(
          config: config,
          selectedName: selectedName,
          onSelect: (name) => controller.selectProvider(name),
          onAdd: () => _addProvider(context, controller),
          onDelete: (name) => _deleteProvider(context, controller, name),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _ProviderDetailPanel(
            config: config,
            provider: selectedProvider,
            controller: controller,
            onSave: (name, provider) {
              controller.updateProvider(name, provider);
            },
            onDelete: (name) {
              _deleteProvider(context, controller, name);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addProvider(
    BuildContext context,
    LlmConfigController controller,
  ) async {
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
        !controller.config.providers.containsKey(name)) {
      controller.addProvider(
        LlmProviderConfig(name: name, type: 'api', providerType: 'openai'),
      );
      controller.selectProvider(name);
    }
  }

  Future<void> _deleteProvider(
    BuildContext context,
    LlmConfigController controller,
    String name,
  ) async {
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
      controller.deleteProvider(name);
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

    return SizedBox(
      width: 180,
      child: Container(
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
                border: Border(
                  bottom: BorderSide(color: colors.tabBarDivider),
                ),
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
  });

  final LlmConfig config;
  final LlmProviderConfig? provider;
  final LlmConfigController controller;
  final void Function(String name, LlmProviderConfig provider) onSave;
  final ValueChanged<String> onDelete;

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
    _apiKeyController.text =
        provider.apiKey.isEmpty ? '' : LlmConfig.maskedSecret;
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
              border: Border(
                bottom: BorderSide(color: colors.tabBarDivider),
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
                            controller: TextEditingController(
                              text: _providerType,
                            )..selection = TextSelection.collapsed(
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
                            obscureText:
                                !_apiKeyRevealed && _apiKey.isNotEmpty,
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
                                            _apiKeyRevealed =
                                                !_apiKeyRevealed;
                                            if (_apiKeyRevealed &&
                                                !_apiKeyReplaced) {
                                              _apiKeyController.text =
                                                  widget.controller
                                                      .revealApiKey(
                                                        provider.name,
                                                      );
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
                                key:
                                    index == 0
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
      builder:
          (context) => _ModelEditDialog(
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

// --- Models tab ---

class _ModelsTabContent extends StatelessWidget {
  const _ModelsTabContent({required this.controller});

  final LlmConfigController controller;

  @override
  Widget build(BuildContext context) {
    final config = controller.config;
    return _ModelsTable(
      config: config,
      onAdd: () => _addModel(context, controller),
      onUpdate: (id, model) {
        controller.updateModel(id, model);
      },
      onDelete: (id) {
        controller.deleteModel(id);
      },
    );
  }

  Future<void> _addModel(
    BuildContext context,
    LlmConfigController controller,
  ) async {
    final l10n = context.l10n;
    final defaultProvider = controller.config.providers.keys.firstOrNull ?? '';
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder:
          (context) => _ModelEditDialog(
            providers: controller.config.providers,
            defaultProvider: defaultProvider,
            title: l10n.addModel,
          ),
    );
    if (result != null) {
      controller.addModel(result);
    }
  }
}

class _ModelsTable extends StatelessWidget {
  const _ModelsTable({
    required this.config,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
  });

  final LlmConfig config;
  final VoidCallback onAdd;
  final void Function(String, LlmModelConfig) onUpdate;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final models = config.models.values.toList();
    final headerStyle = TextStyle(
      color: textBase.withValues(alpha: 0.58),
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    );

    return Container(
      key: AppKeys.llmModelsTable,
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.tabBarDivider),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.models,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textBase,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onAdd,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: textBase.withValues(alpha: 0.04),
            child: Row(
              children: [
                const SizedBox(width: 10),
                Expanded(flex: 3, child: Text(l10n.name, style: headerStyle)),
                Expanded(
                  flex: 2,
                  child: Text(l10n.provider, style: headerStyle),
                ),
                Expanded(
                  flex: 3,
                  child: Text(l10n.actualModel, style: headerStyle),
                ),
                SizedBox(
                  width: 80,
                  child: Text(l10n.enabled, style: headerStyle),
                ),
                const SizedBox(width: 80),
              ],
            ),
          ),
          Expanded(
            child: models.isEmpty
                ? Center(
                    child: Text(
                      l10n.noModelsConfigured,
                      style: TextStyle(color: colors.emptyMessageText),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: models.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final model = models[index];
                      final providerExists =
                          config.providers.containsKey(model.provider);
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            if (!providerExists)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Tooltip(
                                  message:
                                      '${l10n.missingProvider} ${model.provider}',
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 14,
                                    color: Color(0xFFFDE68A),
                                  ),
                                ),
                              ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                model.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                model.provider,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: providerExists
                                      ? null
                                      : const Color(0xFFFCA5A5),
                                ),
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
                              width: 80,
                              child: Switch(
                                value: model.enabled,
                                onChanged: (value) {
                                  onUpdate(
                                    model.id,
                                    model.copyWith(enabled: value),
                                  );
                                },
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: AppKeys.editModelButton(model.id),
                                    tooltip: l10n.edit,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      _editModel(context, model);
                                    },
                                  ),
                                  IconButton(
                                    key: AppKeys.deleteModelButton(model.id),
                                    tooltip: l10n.delete,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      onDelete(model.id);
                                    },
                                  ),
                                ],
                              ),
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

  Future<void> _editModel(BuildContext context, LlmModelConfig model) async {
    final l10n = context.l10n;
    final result = await showDialog<LlmModelConfig>(
      context: context,
      builder:
          (context) => _ModelEditDialog(
            model: model,
            providers: config.providers,
            title: l10n.editModelTitle(model.name),
          ),
    );
    if (result != null) {
      onUpdate(model.id, result);
    }
  }
}

// --- Raw JSON tab ---

class _RawJsonTabContent extends StatelessWidget {
  const _RawJsonTabContent({required this.controller});

  final LlmConfigController controller;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final config = controller.config;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: SelectableText(
        key: AppKeys.llmRawJsonPreview,
        config.toMaskedJsonString(),
        style: TextStyle(
          color: textBase.withValues(alpha: 0.72),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}

// --- Side panel (always visible) ---

class _LlmSidePanel extends StatelessWidget {
  const _LlmSidePanel({required this.config});

  final LlmConfig config;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final messages = config.validationMessages;
    final missingRefs = config.models.values
        .where((m) => !config.providers.containsKey(m.provider))
        .length;
    final emptyKeys = config.providers.values
        .where((p) => p.type == 'api' && p.apiKey.trim().isEmpty)
        .length;
    final jsonString = config.toMaskedJsonString();
    final jsonSnippet = jsonString.length > 500
        ? '${jsonString.substring(0, 500)}...'
        : jsonString;

    return Container(
      key: AppKeys.llmSidePanel,
      color: colors.rightPanelBackground,
      child: Column(
        children: [
          Expanded(
            flex: 35,
            child: Container(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.summary,
                    style: TextStyle(
                      color: textBase.withValues(alpha: 0.58),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      key: AppKeys.llmSummaryStats,
                      child: GridView.count(
                        crossAxisCount: 2,
                        childAspectRatio: 1.8,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        children: [
                          _StatBox(
                            value: '${config.providers.length}',
                            label: l10n.statProviders,
                          ),
                          _StatBox(
                            value: '${config.models.length}',
                            label: l10n.statModels,
                          ),
                          _StatBox(
                            value: '$missingRefs',
                            label: l10n.statMissingRefs,
                            warn: missingRefs > 0,
                          ),
                          _StatBox(
                            value: '$emptyKeys',
                            label: l10n.statEmptyKeys,
                            warn: emptyKeys > 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: colors.subtleBorder),
          Expanded(
            flex: 32,
            child: Container(
              key: AppKeys.llmValidationSummary,
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.validation,
                    style: TextStyle(
                      color: textBase.withValues(alpha: 0.58),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: messages.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colors.successBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colors.successBorder,
                              ),
                            ),
                            child: Text(
                              l10n.allChecksPassed,
                              style: TextStyle(
                                color: colors.successText,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: messages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) => Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colors.warningBackground,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colors.warningBorder,
                                ),
                              ),
                              child: Text(
                                messages[index],
                                style: const TextStyle(
                                  color: Color(0xFFFDE68A),
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: colors.subtleBorder),
          Expanded(
            flex: 33,
            child: Container(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.jsonPreview,
                    style: TextStyle(
                      color: textBase.withValues(alpha: 0.58),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colors.codeBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          jsonSnippet,
                          style: TextStyle(
                            color: colors.accentGreenLight,
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.value,
    required this.label,
    this.warn = false,
  });

  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.statBoxBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: warn ? colors.statBoxWarnBorder : colors.statBoxBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: warn ? const Color(0xFFFDE68A) : textBase,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: textBase.withValues(alpha: 0.54),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
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
              value:
                  widget.providers.containsKey(_provider) ? _provider : null,
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
  const _WorkspaceHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
