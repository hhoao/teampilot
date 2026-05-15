import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/l10n_extensions.dart';
import '../models/llm_config.dart';
import '../cubits/llm_config_cubit.dart';
import '../utils/app_keys.dart';
import '../widgets/app_outline_text_field.dart';
import '../widgets/dropdown/custom_dropdown.dart';
import '../widgets/dropdown/flashskyai_dropdown_decoration.dart';
import '../widgets/resizable_split_view.dart';

// LLM 配置页统一留白（8dp 网格）。
const double _kLlmInsetH = 16;
const double _kLlmInsetHSm = 12;
const double _kLlmSectionGap = 12;
const double _kLlmFieldGap = 8;

class LlmConfigWorkspace extends StatelessWidget {
  const LlmConfigWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LlmConfigCubit>();
    return Column(
      key: AppKeys.llmConfigWorkspace,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConfigPathBar(controller: controller),
        Expanded(child: _ProvidersTabContent(controller: controller)),
      ],
    );
  }
}

class _ConfigPathBar extends StatefulWidget {
  const _ConfigPathBar({required this.controller});

  final LlmConfigCubit controller;

  @override
  State<_ConfigPathBar> createState() => _ConfigPathBarState();
}

class _ConfigPathBarState extends State<_ConfigPathBar> {
  late final TextEditingController _textController;
  String _lastSyncedOverride = '';

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.controller.state.configPathOverride,
    );
    _lastSyncedOverride = widget.controller.state.configPathOverride;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _syncFromState(LlmConfigState state) {
    if (state.configPathOverride != _lastSyncedOverride) {
      _lastSyncedOverride = state.configPathOverride;
      _textController.value = TextEditingValue(
        text: state.configPathOverride,
        selection: TextSelection.collapsed(
          offset: state.configPathOverride.length,
        ),
      );
    }
  }

  Future<void> _pickFile(AppLocalizations l10n) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.llmConfigPathPickerTitle,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final picked = result?.files.single.path;
    if (picked == null) return;
    _textController.text = picked;
    await widget.controller.setConfigPath(picked);
  }

  Future<void> _apply() async {
    await widget.controller.setConfigPath(_textController.text);
  }

  Future<void> _reset() async {
    _textController.clear();
    await widget.controller.setConfigPath(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.controller.state;
    _syncFromState(state);

    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final badgeText = state.isUsingCustomPath
        ? l10n.llmConfigPathBadgeCustom
        : l10n.llmConfigPathBadgeDefault;
    final badgeColor = state.isUsingCustomPath
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        _kLlmInsetHSm,
        _kLlmFieldGap + 2,
        _kLlmInsetHSm,
        _kLlmFieldGap + 2,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.llmConfigPathLabel,
                style: _LlmWorkspaceText(theme).bodyStrong,
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  badgeText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: badgeColor,
                  ),
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: state.effectiveConfigPath,
                  waitDuration: const Duration(milliseconds: 400),
                  child: SelectionArea(
                    child: Text(
                      state.effectiveConfigPath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AppOutlineTextField(
                  controller: _textController,
                  hintText: l10n.llmConfigPathHint,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () => _pickFile(l10n),
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(l10n.llmConfigPathBrowse),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: state.isLoading ? null : _apply,
                child: Text(l10n.llmConfigPathSave),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: state.isLoading || !state.isUsingCustomPath
                    ? null
                    : _reset,
                child: Text(l10n.llmConfigPathReset),
              ),
            ],
          ),
        ],
      ),
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

    final showModels =
        _modelsProviderName != null &&
        selectedProvider != null &&
        _modelsProviderName == selectedProvider.name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ResizableSplitView(
        initialLeftFraction: 0.34,
        minLeftWidth: 220,
        maxLeftWidth: 560,
        left: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: _ProviderListPanel(
            config: config,
            selectedName: selectedName,
            onSelect: (name) {
              _controller.selectProvider(name);
              setState(() => _modelsProviderName = null);
            },
            onAdd: () => _addProvider(context),
            onDelete: (name) => _deleteProvider(context, name),
          ),
        ),
        right: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: showModels
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
        ),
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
        content: AppOutlineTextField(
          key: AppKeys.providerNameDialogField,
          controller: nameController,
          autofocus: true,
          labelText: l10n.providerName,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tx = _LlmWorkspaceText(theme);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final rawList = widget.config.providers.values
        .where(
          (p) =>
              _searchQuery.isEmpty ||
              p.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    // 防御：若底层 Map 因异常出现同名多条，避免 ListView 子 Element 复用错乱。
    final providers = <LlmProviderConfig>[];
    final seenNames = <String>{};
    for (final p in rawList) {
      if (seenNames.add(p.name)) providers.add(p);
    }

    return Container(
      key: AppKeys.llmProviderList,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.providerList,
                    style: tx.panelHeaderColored(textBase),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.onAdd,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        '+ ${l10n.add}',
                        style: tx.smallColored(
                          cs.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: AppOutlineTextField(
              key: AppKeys.llmProviderSearch,
              controller: _searchController,
              hintText: l10n.filterProviders,
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              itemCount: providers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final provider = providers[index];
                final isSelected = provider.name == widget.selectedName;
                final modelCount = widget.config.models.values
                    .where((m) => m.provider == provider.name)
                    .length;
                return _ProviderListRow(
                  key: ObjectKey(provider),
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
    super.key,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tx = _LlmWorkspaceText(theme);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      color: isSelected
          ? cs.primaryContainer
          : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? cs.primaryContainer
                  : cs.outlineVariant,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tx.bodyStrongColored(textBase),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _TypeBadge(
                          key: ValueKey<String>(
                            'list-badge-${provider.name}-${provider.type}',
                          ),
                          type: provider.type,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.providerListCaption(
                              modelCount,
                              provider.proxy,
                            ),
                            key: ValueKey<String>(
                              'list-cap-${provider.name}-$modelCount-${provider.proxy}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tx.smallColored(
                              textBase.withValues(alpha: 0.48),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey<String>('prov-menu-${provider.name}'),
                icon: const Icon(Icons.more_horiz, size: 18),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tx = _LlmWorkspaceText(theme);
    final isAccount = type == 'account';
    final smallFontSize = tx.small.fontSize ?? 11;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        color: isAccount ? cs.secondaryContainer : cs.primaryContainer,
        border: Border.all(
          color: isAccount
              ? cs.secondaryContainer
              : cs.primaryContainer,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          type,
          strutStyle: StrutStyle(
            fontSize: smallFontSize,
            height: 1.0,
            forceStrutHeight: true,
            leading: 0,
          ),
          style: tx.small.copyWith(
            height: 1.0,
            letterSpacing: 0.2,
            fontWeight: FontWeight.w600,
            color: isAccount
                ? cs.onSecondaryContainer
                : cs.onPrimaryContainer,
          ),
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
  late final TextEditingController _providerTypeController;
  late final TextEditingController _baseUrlController;
  late String _apiKey;
  late bool _proxy;
  late final TextEditingController _proxyUrlController;
  late final TextEditingController _apiKeyController;
  late List<TextEditingController> _accountControllers;
  bool _apiKeyRevealed = false;
  bool _apiKeyReplaced = false;
  String? _providerName;
  Timer? _persistDebounce;

  @override
  void initState() {
    super.initState();
    _providerTypeController = TextEditingController();
    _baseUrlController = TextEditingController();
    _proxyUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    _accountControllers = [];
    _syncFromProvider();
  }

  @override
  void didUpdateWidget(covariant _ProviderDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prev = oldWidget.provider;
    final next = widget.provider;
    if (prev?.name != next?.name) {
      _persistDebounce?.cancel();
      _persistDebounce = null;
      if (prev != null && _providerName == prev.name) {
        widget.onSave(prev.name, _draftFromFieldsFor(prev));
      }
    }
    if (widget.provider?.name != _providerName) {
      _syncFromProvider();
    }
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    final p = widget.provider;
    if (p != null && _providerName == p.name) {
      widget.onSave(p.name, _draftFromFieldsFor(p));
    }
    _providerTypeController.dispose();
    _baseUrlController.dispose();
    _proxyUrlController.dispose();
    _apiKeyController.dispose();
    for (final c in _accountControllers) {
      c.dispose();
    }
    super.dispose();
  }

  static const _persistDebounceDuration = Duration(milliseconds: 450);

  void _persistDebounced() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(_persistDebounceDuration, () {
      if (!mounted) return;
      _persistProvider();
    });
  }

  /// 取消防抖并立即写入（例如提交键盘、切换 Provider 前）。
  void _flushPersistDebounce() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    _persistProvider();
  }

  void _persistProvider() {
    final provider = widget.provider;
    if (provider == null) return;
    widget.onSave(provider.name, _draftFromFieldsFor(provider));
  }

  /// 用当前表单控件状态，生成以 [base] 为起点的配置（切换 Provider 时 [base] 须为旧项，不能再用 [widget.provider]）。
  LlmProviderConfig _draftFromFieldsFor(LlmProviderConfig base) {
    return base.copyWith(
      type: _type,
      providerType: _type == 'api' ? _providerTypeController.text : '',
      baseUrl: _type == 'api' ? _baseUrlController.text : '',
      apiKey: _type == 'api' ? _apiKey : '',
      proxy: _proxy,
      proxyUrl: _proxy ? _proxyUrlController.text : '',
      accounts: _type == 'account'
          ? _accountControllers.map((c) => c.text).toList()
          : const [],
    );
  }

  void _syncFromProvider() {
    _persistDebounce?.cancel();
    final provider = widget.provider;
    if (provider == null) {
      _providerName = null;
      return;
    }
    _providerName = provider.name;
    _type = provider.type;
    _providerTypeController.text = provider.providerType;
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
    final look = _ProviderDetailLook.of(context);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final provider = widget.provider;

    if (provider == null) {
      return Container(
        key: AppKeys.llmProviderDetail,
        decoration: BoxDecoration(
          color: look.panelBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: look.borderColor),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.selectProvider,
              textAlign: TextAlign.center,
              style: look.mutedBodyStyle.copyWith(height: 1.4),
            ),
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
        color: look.panelBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: look.borderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _kLlmInsetH,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Tooltip(
                              message: provider.name,
                              waitDuration: const Duration(milliseconds: 400),
                              child: Text(
                                provider.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: look.panelTitleStyle,
                              ),
                            ),
                          ),
                          const SizedBox(width: _kLlmFieldGap),
                          _TypeBadge(
                            key: ValueKey<String>(
                              'hdr-${provider.name}-${provider.type}',
                            ),
                            type: provider.type,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.providerDetailSubtitle(
                          providerModels.length,
                          _type == 'api' ? l10n.api : l10n.account,
                        ),
                        style: look.mutedBodyStyle,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => widget.onShowModels(provider.name),
                  icon: const Icon(Icons.model_training_outlined, size: 17),
                  label: Text(l10n.models),
                ),
                const SizedBox(width: _kLlmFieldGap),
                IconButton(
                  tooltip: l10n.deleteProviderTooltip,
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => widget.onDelete(provider.name),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                _kLlmInsetH,
                _kLlmSectionGap,
                _kLlmInsetH,
                _kLlmInsetH,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trailingW = (constraints.maxWidth * 0.42).clamp(
                    200.0,
                    320.0,
                  );

                  String typeLabel(String v) =>
                      v == 'api' ? l10n.api : l10n.account;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SettingRow(
                        title: l10n.providerName,
                        trailing: SizedBox(
                          width: trailingW,
                          child: _InlineReadOnlyValue(value: provider.name),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: theme.dividerColor.withValues(alpha: 0.35),
                        ),
                      ),
                      _SettingRow(
                        title: l10n.type,
                        trailing: SizedBox(
                          width: trailingW,
                          child: Builder(
                            builder: (context) {
                              final deco =
                                  FlashskyDropdownDecorations.denseField(
                                    context,
                                  );
                              return DropdownFlutter<String>(
                                key: ValueKey<String>(
                                  'provider-type-${provider.name}',
                                ),
                                items: const ['api', 'account'],
                                initialItem: _type,
                                excludeSelected: false,
                                decoration: deco,
                                closedHeaderPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                expandedHeaderPadding:
                                    const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                listItemPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 10,
                                ),
                                overlayHeight: 160,
                                onChanged: (value) {
                                  setState(() => _type = value ?? 'api');
                                  _persistProvider();
                                },
                                headerBuilder: (context, value, _) => Text(
                                  typeLabel(value),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: deco.headerStyle,
                                ),
                                listItemBuilder: (context, value, _, __) {
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          typeLabel(value),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: deco.listItemStyle,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      if (_type == 'api') ...[
                        _SettingFieldBlock(
                          title: l10n.providerType,
                          child: AppOutlineTextField(
                            key: AppKeys.providerTypeField,
                            controller: _providerTypeController,
                            hintText: l10n.providerTypeHint,
                            onChanged: (_) => _persistDebounced(),
                            onSubmitted: (_) => _flushPersistDebounce(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.dividerColor.withValues(alpha: 0.35),
                          ),
                        ),
                        _SettingRow(
                          title: l10n.proxy,
                          trailing: Switch(
                            key: AppKeys.providerProxyToggle,
                            value: _proxy,
                            onChanged: (value) {
                              setState(() => _proxy = value);
                              _persistProvider();
                            },
                          ),
                        ),
                        if (_proxy) ...[
                          _SettingFieldBlock(
                            title: l10n.proxyUrl,
                            child: AppOutlineTextField(
                              key: AppKeys.proxyUrlField,
                              controller: _proxyUrlController,
                              onChanged: (_) => _persistDebounced(),
                              onSubmitted: (_) => _flushPersistDebounce(),
                            ),
                          ),
                        ],
                        _SettingFieldBlock(
                          title: l10n.baseUrl,
                          child: AppOutlineTextField(
                            key: AppKeys.baseUrlField,
                            controller: _baseUrlController,
                            onChanged: (_) => _persistDebounced(),
                            onSubmitted: (_) => _flushPersistDebounce(),
                          ),
                        ),
                        _SettingFieldBlock(
                          title: l10n.apiKey,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: AppOutlineTextField(
                                  key: AppKeys.apiKeyField,
                                  controller: _apiKeyController,
                                  obscureText:
                                      !_apiKeyRevealed && _apiKey.isNotEmpty,
                                  suffixIcon: _apiKey.isNotEmpty
                                      ? IconButton(
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
                                              _apiKeyController.text = widget
                                                  .controller
                                                  .revealApiKey(
                                                    provider.name,
                                                  );
                                            } else if (!_apiKeyRevealed) {
                                              _apiKeyController.text =
                                                  LlmConfig.maskedSecret;
                                            }
                                          }),
                                        )
                                      : null,
                                  onChanged: (value) {
                                    if (value != LlmConfig.maskedSecret) {
                                      _apiKey = value;
                                      _apiKeyReplaced = true;
                                    }
                                    _persistDebounced();
                                  },
                                  onSubmitted: (_) => _flushPersistDebounce(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                key: AppKeys.replaceApiKeyButton,
                                tooltip: l10n.replaceKey,
                                onPressed: () {
                                  setState(() {
                                    _apiKeyController.clear();
                                    _apiKey = '';
                                    _apiKeyRevealed = true;
                                    _apiKeyReplaced = true;
                                  });
                                  _persistProvider();
                                },
                                icon: const Icon(Icons.key_outlined),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_type == 'account') ...[
                        const SizedBox(height: _kLlmSectionGap),
                        ...List.generate(_accountControllers.length, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: AppOutlineTextField(
                                    key: index == 0
                                        ? AppKeys.accountPathField
                                        : null,
                                    controller: _accountControllers[index],
                                    hintText: l10n.accountCredentialPath,
                                    onChanged: (_) => _persistDebounced(),
                                    onSubmitted: (_) =>
                                        _flushPersistDebounce(),
                                  ),
                                ),
                                IconButton(
                                  key: AppKeys.deleteAccountPathButton,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  tooltip: l10n.removePath,
                                  onPressed: () {
                                    setState(() {
                                      _accountControllers[index].dispose();
                                      _accountControllers.removeAt(index);
                                    });
                                    _persistProvider();
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: AppKeys.addAccountPathButton,
                            onPressed: () {
                              setState(
                                () => _accountControllers.add(
                                  TextEditingController(),
                                ),
                              );
                              _persistDebounced();
                            },
                            icon: const Icon(Icons.add),
                            label: Text(l10n.addAccountPath),
                          ),
                        ),
                      ],
                      const SizedBox(height: _kLlmSectionGap),
                      if (providerModels.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Divider(
                            height: 1,
                            thickness: 1,
                            color: theme.dividerColor.withValues(alpha: 0.35),
                          ),
                        ),
                        Text(
                          l10n.modelsUsingProviderTitle,
                          style: look.sectionTitleStyle,
                        ),
                        const SizedBox(height: _kLlmFieldGap),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: look.insetPanelBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: look.insetPanelBorder),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(_kLlmInsetHSm),
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
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _kLlmInsetH,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: look.insetPanelBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: look.insetPanelBorder),
                          ),
                          child: Text(
                            l10n.noModelsUsingProvider,
                            style: look.mutedBodyStyle.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// 本页排版：沿用 [ThemeData.textTheme]，仅「小 / 中 / 面板标题」三档字号来源；
/// 字重只在 regular、[FontWeight.w500]、[FontWeight.w600] 之间选（不出现 w700/w800）。
class _LlmWorkspaceText {
  const _LlmWorkspaceText(this.theme);

  final ThemeData theme;

  TextTheme get _t => theme.textTheme;

  TextStyle get _smallBase => _t.labelSmall ?? const TextStyle();

  /// 小：徽章、次要说明、紧凑链接。
  TextStyle get small => _smallBase.copyWith(height: 1.35);

  TextStyle smallColored(Color color, {FontWeight? fontWeight}) =>
      small.copyWith(color: color, fontWeight: fontWeight);

  /// 中：正文、只读值。
  TextStyle get body {
    final base = _t.bodyMedium ?? const TextStyle(fontSize: 14);
    return base.copyWith(height: 1.35);
  }

  TextStyle bodyColored(Color color) => body.copyWith(color: color);

  /// 中强调：行标题、列表主名称。
  TextStyle get bodyStrong =>
      body.copyWith(fontWeight: FontWeight.w600, height: 1.25);

  TextStyle bodyStrongColored(Color color) =>
      bodyStrong.copyWith(color: color);

  /// 面板顶栏标题（不做更大字号档位）。
  TextStyle get panelHeader {
    final base = _t.titleSmall ?? _t.titleMedium ?? const TextStyle();
    return base.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.15,
      height: 1.25,
    );
  }

  TextStyle panelHeaderColored(Color color) =>
      panelHeader.copyWith(color: color);

  TextStyle get mutedBody =>
      body.copyWith(color: theme.colorScheme.onSurfaceVariant);

  TextStyle get mutedSmall =>
      small.copyWith(color: theme.colorScheme.onSurfaceVariant);
}

/// Provider detail pane: typography and [ColorScheme] from app [ThemeData].
class _ProviderDetailLook {
  const _ProviderDetailLook._(this.theme);

  factory _ProviderDetailLook.of(BuildContext context) {
    return _ProviderDetailLook._(Theme.of(context));
  }

  final ThemeData theme;

  _LlmWorkspaceText get _tx => _LlmWorkspaceText(theme);

  ColorScheme get colorScheme => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;

  Color get panelBg => colorScheme.surfaceContainer;

  Color get borderColor => colorScheme.outlineVariant;

  Color get insetPanelBg => colorScheme.surfaceContainerHigh;

  Color get insetPanelBorder => colorScheme.outlineVariant;

  TextStyle get panelTitleStyle =>
      _tx.panelHeaderColored(colorScheme.onSurface);

  TextStyle get mutedBodyStyle => _tx.mutedSmall;

  TextStyle get rowLabelStyle =>
      _tx.bodyStrongColored(colorScheme.onSurface).copyWith(height: 1.2);

  TextStyle get sectionTitleStyle =>
      _tx.panelHeaderColored(colorScheme.onSurface);

  /// 只读字段内文字：中档 + 弱化色。
  TextStyle get valueBoxStyle => _tx.mutedBody;
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.trailing});

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final look = _ProviderDetailLook.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final labelW = (c.maxWidth * 0.30).clamp(104.0, 152.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: labelW,
                child: Text(
                  title,
                  style: look.rowLabelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: trailing,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InlineReadOnlyValue extends StatelessWidget {
  const _InlineReadOnlyValue({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final look = _ProviderDetailLook.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: look.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: look.colorScheme.outlineVariant),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: look.valueBoxStyle,
      ),
    );
  }
}

class _SettingFieldBlock extends StatelessWidget {
  const _SettingFieldBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final look = _ProviderDetailLook.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: look.rowLabelStyle),
          const SizedBox(height: 6),
          child,
        ],
      ),
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
    final theme = Theme.of(context);
    final tx = _LlmWorkspaceText(theme);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final model in models)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx.bodyStrongColored(textBase),
                      ),
                      if (model.model.isNotEmpty &&
                          model.model != model.name) ...[
                        const SizedBox(height: 2),
                        Text(
                          model.model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tx.smallColored(muted),
                        ),
                      ],
                    ],
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tx = _LlmWorkspaceText(theme);
    final l10n = context.l10n;
    final isDark = theme.brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final providerModels = config.models.values
        .where((m) => m.provider == provider.name)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.back,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${l10n.models} — ${provider.name}',
                        style: tx.panelHeaderColored(textBase),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${providerModels.length} ${l10n.models.toLowerCase()}',
                        style: tx.smallColored(
                          textBase.withValues(alpha: 0.48),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _addModel(context, provider.name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        '+ ${l10n.add}',
                        style: tx.smallColored(
                          cs.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: providerModels.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(_kLlmInsetH),
                      child: Text(
                        l10n.noModelsConfigured,
                        style: tx.mutedBody,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: providerModels.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final model = providerModels[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: textBase.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
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
                                    style: tx.bodyStrongColored(textBase),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    model.model,
                                    style: tx.smallColored(
                                      textBase.withValues(alpha: 0.54),
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
                itemBuilder: (context, index) {
                  final body = Theme.of(context).textTheme.bodyMedium;
                  return Text(
                    '${index + 1}. ${messages[index]}',
                    style: (body ?? const TextStyle()).copyWith(height: 1.35),
                  );
                },
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
    final providerNames = widget.providers.keys.toList()..sort();
    final deco = FlashskyDropdownDecorations.denseField(context);
    final initialProvider = widget.providers.containsKey(_provider)
        ? _provider
        : null;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppOutlineTextField(
              key: AppKeys.modelNameDialogField,
              controller: _nameController,
              autofocus: true,
              labelText: l10n.modelName,
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.provider,
                  style: _LlmWorkspaceText(Theme.of(context)).bodyStrong,
                ),
                const SizedBox(height: 8),
                DropdownFlutter<String>(
                  key: AppKeys.modelProviderField,
                  items: providerNames,
                  initialItem: initialProvider,
                  hintText: l10n.provider,
                  excludeSelected: false,
                  decoration: deco,
                  closedHeaderPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  expandedHeaderPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  listItemPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  overlayHeight: 260,
                  onChanged: (value) => setState(() => _provider = value ?? ''),
                  headerBuilder: (context, value, _) => Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: deco.headerStyle,
                  ),
                  listItemBuilder: (context, value, _, __) {
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: deco.listItemStyle,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppOutlineTextField(
              key: AppKeys.modelModelIdField,
              controller: _modelController,
              labelText: l10n.modelId,
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
  const _WorkspaceHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = _LlmWorkspaceText(theme);
    final isDark = theme.brightness == Brightness.dark;
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
                style: tx.panelHeaderColored(textBase),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: tx.bodyColored(textBase.withValues(alpha: 0.64)),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
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
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}
