import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/app_provider_cubit.dart';
import '../../../cubits/team_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../services/app/onboarding_service.dart';
import '../../../models/app_provider_config.dart';
import '../../../services/provider/claude_official_provider.dart';
import '../../../utils/app_provider_model_candidates.dart';
import '../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';

class OnboardingDefaultProviderStep extends StatefulWidget {
  const OnboardingDefaultProviderStep({super.key});

  @override
  State<OnboardingDefaultProviderStep> createState() =>
      _OnboardingDefaultProviderStepState();
}

class _OnboardingDefaultProviderStepState
    extends State<OnboardingDefaultProviderStep> {
  String? _selectedProviderId;
  String _defaultModel = '';
  final _haikuController = TextEditingController();
  final _sonnetController = TextEditingController();
  final _opusController = TextEditingController();
  AppProviderCubit? _appProviderCubit;
  TeamCubit? _teamCubit;

  @override
  void initState() {
    super.initState();
    _syncFromCubit();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appProviderCubit = context.read<AppProviderCubit>();
    _teamCubit = context.read<TeamCubit>();
  }

  @override
  void dispose() {
    _haikuController.dispose();
    _sonnetController.dispose();
    _opusController.dispose();
    super.dispose();
  }

  List<AppProviderConfig> get _providers =>
      _appProviderCubit?.state.providersFor(AppProviderCli.claude) ??
      const [];

  AppProviderConfig? get _selectedProvider {
    final id = _selectedProviderId;
    if (id == null) return null;
    for (final provider in _providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  bool get _hideModelPicker {
    final provider = _selectedProvider;
    return provider != null && isOfficialClaudeProvider(provider);
  }

  void _syncFromCubit() {
    final cubit = _appProviderCubit ?? context.read<AppProviderCubit>();
    final providers = cubit.state.providersFor(AppProviderCli.claude);
    final selectedId =
        cubit.state.selectedProviderIdByCli[AppProviderCli.claude];
    final initialId =
        selectedId != null && providers.any((p) => p.id == selectedId)
        ? selectedId
        : providers.firstOrNull?.id;
    _selectedProviderId = initialId;
    _loadProviderFields(_selectedProvider);
  }

  void _loadProviderFields(AppProviderConfig? provider) {
    final isOfficial = provider != null && isOfficialClaudeProvider(provider);
    _defaultModel = isOfficial ? '' : (provider?.defaultModel ?? '');
    final env = _readEnv(provider);
    _haikuController.text = env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] ?? '';
    _sonnetController.text = env['ANTHROPIC_DEFAULT_SONNET_MODEL'] ?? '';
    _opusController.text = env['ANTHROPIC_DEFAULT_OPUS_MODEL'] ?? '';
  }

  Map<String, String> _readEnv(AppProviderConfig? provider) {
    final raw = provider?.config['env'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
  }

  Future<void> _applySelection() async {
    if (!mounted) return;
    final provider = _selectedProvider;
    if (provider == null) return;

    final cubit = _appProviderCubit;
    final teamCubit = _teamCubit;
    if (cubit == null || teamCubit == null) return;
    cubit.selectProvider(provider.id);

    final env = Map<String, Object?>.from(_readEnv(provider));
    if (_haikuController.text.trim().isNotEmpty) {
      env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = _haikuController.text.trim();
    }
    if (_sonnetController.text.trim().isNotEmpty) {
      env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = _sonnetController.text.trim();
    }
    if (_opusController.text.trim().isNotEmpty) {
      env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = _opusController.text.trim();
    }

    final isOfficial = isOfficialClaudeProvider(provider);
    await cubit.upsertProvider(
      provider.copyWith(
        defaultModel: isOfficial ? '' : _defaultModel.trim(),
        config: {...provider.config, if (env.isNotEmpty) 'env': env},
      ),
    );
    if (!mounted) return;
    await OnboardingService.applyDefaultClaudeProviderBinding(
      appProviderCubit: cubit,
      teamCubit: teamCubit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final providers = _providers;

    if (providers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.onboardingDefaultProviderTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.onboardingDefaultProviderEmpty,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final selectedProvider = _selectedProvider;
    final hideModelPicker = _hideModelPicker;
    final modelNames = selectedProvider == null || hideModelPicker
        ? const <String>[]
        : collectClaudeModelCandidates(
            selectedProvider,
            currentModel: _defaultModel,
          );
    final showClaudeModels =
        _haikuController.text.isNotEmpty ||
        _sonnetController.text.isNotEmpty ||
        _opusController.text.isNotEmpty ||
        _readEnv(selectedProvider).isNotEmpty;
    final showModelSection = !hideModelPicker;
    final dropdownDeco = AppDropdownDecorations.themed(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onboardingDefaultProviderTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.onboardingDefaultProviderSubtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroupHeader(title: l10n.appProviderToolClaude),
              SettingsLabeledRow(
                title: l10n.provider,
                subtitle: l10n.onboardingDefaultProviderPick,
                trailing: SettingsCompactDropdown<String>(
                  value: _selectedProviderId ?? providers.first.id,
                  entries: [
                    for (final provider in providers)
                      (provider.id, provider.name),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedProviderId = value;
                      _loadProviderFields(_selectedProvider);
                    });
                    unawaited(_applySelection());
                  },
                ),
                showDividerBelow: showModelSection,
              ),
              if (showModelSection) ...[
                SettingsLabeledStackedRow(
                  title: l10n.defaultModel,
                  subtitle: l10n.onboardingDefaultProviderModelHint,
                  body: modelNames.isEmpty
                      ? Text(
                          l10n.selectModel,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        )
                      : AppDropdownField<String>(
                          items: modelNames,
                          initialItem: _defaultModel.isEmpty
                              ? null
                              : _defaultModel,
                          hintText: l10n.selectModel,
                          decoration: dropdownDeco,
                          onChanged: (value) {
                            setState(() => _defaultModel = value ?? '');
                            unawaited(_applySelection());
                          },
                          itemLabel: (value) => value,
                        ),
                  showDividerBelow: showClaudeModels,
                ),
              ],
              if (showClaudeModels) ...[
                SettingsLabeledStackedRow(
                  title: l10n.appProviderClaudeHaikuModel,
                  subtitle: l10n.appProviderClaudeModelMappingHint,
                  body: TextField(
                    controller: _haikuController,
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (_) => unawaited(_applySelection()),
                  ),
                  showDividerBelow: true,
                ),
                SettingsLabeledStackedRow(
                  title: l10n.appProviderClaudeSonnetModel,
                  subtitle: l10n.appProviderClaudeModelMappingHint,
                  body: TextField(
                    controller: _sonnetController,
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (_) => unawaited(_applySelection()),
                  ),
                  showDividerBelow: true,
                ),
                SettingsLabeledStackedRow(
                  title: l10n.appProviderClaudeOpusModel,
                  subtitle: l10n.appProviderClaudeModelMappingHint,
                  body: TextField(
                    controller: _opusController,
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (_) => unawaited(_applySelection()),
                  ),
                  showDividerBelow: false,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
