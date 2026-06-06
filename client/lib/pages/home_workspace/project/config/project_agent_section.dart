import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/app_provider_cubit.dart';
import '../../../../cubits/project_profile_cubit.dart';
import '../../../../models/app_provider_config.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/project_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../models/team_member_prompt_presets.dart';
import '../../../../services/app/flashskyai_agent_catalog_service.dart';
import '../../../../services/cli/registry/cli_display_name.dart';
import '../../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../../services/provider/claude/claude_official_provider.dart';
import '../../../../services/storage/storage_resolver.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../../utils/app_provider_model_candidates.dart';
import '../../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import '../../../team_config/team_config_cards.dart';
import '../../../team_config/team_config_helpers.dart';

/// Personal-project agent + CLI defaults (backed by [ProjectProfileCubit]).
class ProjectAgentSection extends StatelessWidget {
  const ProjectAgentSection({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProjectProfileCubit>().state;
    if (state.projectId != projectId ||
        state.status == ProjectProfileLoadStatus.loading ||
        state.status == ProjectProfileLoadStatus.idle) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == ProjectProfileLoadStatus.error) {
      return Center(child: Text(state.errorMessage ?? 'Failed to load profile'));
    }
    final profile = state.profile;
    if (profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ProjectAgentConfigForm(
      key: ValueKey(profile.projectId),
      profile: profile,
      cubit: context.read<ProjectProfileCubit>(),
    );
  }
}

class ProjectAgentConfigForm extends StatefulWidget {
  const ProjectAgentConfigForm({
    super.key,
    required this.profile,
    required this.cubit,
  });

  final ProjectProfile profile;
  final ProjectProfileCubit cubit;

  @override
  State<ProjectAgentConfigForm> createState() => ProjectAgentConfigFormState();
}

class ProjectAgentConfigFormState extends State<ProjectAgentConfigForm> {
  late TextEditingController _agentCtl;
  late TextEditingController _argsCtl;
  late TextEditingController _promptCtl;
  List<String> _userAgentIds = const [];

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.profile.agent);
    _loadUserAgents();
  }

  @override
  void didUpdateWidget(covariant ProjectAgentConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.projectId != widget.profile.projectId ||
        oldWidget.profile.agent != widget.profile.agent) {
      _syncControllers(widget.profile.agent);
    }
  }

  Future<void> _loadUserAgents() async {
    final storageRoots = context.read<StorageRoots>();
    final ids = await FlashskyaiAgentCatalogService(
      storageRoots: storageRoots,
    ).listUserAgentIds();
    if (!mounted) return;
    setState(() => _userAgentIds = ids);
  }

  void _syncControllers(ProjectAgentConfig agent) {
    _agentCtl = TextEditingController(text: agent.agent);
    _argsCtl = TextEditingController(text: agent.extraArgs);
    _promptCtl = TextEditingController(text: agent.prompt);
  }

  @override
  void dispose() {
    _agentCtl.dispose();
    _argsCtl.dispose();
    _promptCtl.dispose();
    super.dispose();
  }

  Future<void> _updateAgent(ProjectAgentConfig next) async {
    await widget.cubit.updateAgent(next);
  }

  void _applyPromptPreset(String presetId) {
    final l10n = context.l10n;
    final text = teamMemberPromptPresetText(l10n, presetId);
    if (text.isEmpty) return;
    _promptCtl.text = text;
    _promptCtl.selection = TextSelection.collapsed(offset: text.length);
    unawaited(_updateAgent(widget.profile.agent.copyWith(prompt: text)));
  }

  List<String> _modelNamesForClaudeProvider({
    required String providerId,
    required AppProviderConfig? appProvider,
    required String currentModel,
  }) {
    if (appProvider == null) {
      final trimmed = currentModel.trim();
      return trimmed.isEmpty ? <String>[] : [trimmed];
    }
    return collectClaudeModelCandidates(
      appProvider,
      currentModel: currentModel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profile = widget.profile;
    final agent = profile.agent;
    final catalogCli = catalogCliForTeam(context, profile.cli) ?? CliTool.claude;
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final cliRegistry = CliToolRegistryScope.of(context);

    final prov = agent.provider;
    final appProviders = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(catalogCli)
        .toList(growable: false);
    final providerIds = appProviders.map((p) => p.id).toList()..sort();
    if (prov.trim().isNotEmpty && !providerIds.contains(prov)) {
      providerIds.add(prov);
    }
    final providerLabels = {
      for (final p in appProviders) p.id: p.name,
      if (prov.trim().isNotEmpty && !appProviders.any((p) => p.id == prov))
        prov: prov,
    };

    AppProviderConfig? selectedAppProvider;
    if (prov.trim().isNotEmpty) {
      for (final p in context.read<AppProviderCubit>().state.providersFor(
        catalogCli,
      )) {
        if (p.id == prov) {
          selectedAppProvider = p;
          break;
        }
      }
    }

    final modelNames = List<String>.of(
      _modelNamesForClaudeProvider(
        providerId: prov,
        appProvider: selectedAppProvider,
        currentModel: agent.model,
      ),
    )..sort();
    final hideModelPicker =
        catalogCli == CliTool.claude &&
        selectedAppProvider != null &&
        isOfficialClaudeProvider(selectedAppProvider);

    final showCustomAgentField =
        FlashskyaiAgentCatalog.activeDropdownValue(
          agent.agent,
          userAgentIds: _userAgentIds,
        ) ==
        FlashskyaiAgentCatalog.customDropdownValue;

    return SingleChildScrollView(
      child: TeamConfigCard(
        child: SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TeamConfigCardHeader(title: l10n.homeWorkspaceProjectAgent),
              const SizedBox(height: 8),
              SettingsLabeledStackedRow(
                title: l10n.teamCliLabel,
                subtitle: l10n.teamCliLockedSubtitle,
                body: AppDropdownField<String>(
                  items: [
                    for (final def in cliRegistry.launchable) def.id.value,
                  ],
                  initialItem: profile.cli.value,
                  decoration: dropdownDeco,
                  onChanged: (value) {
                    if (value == null) return;
                    unawaited(widget.cubit.setCli(CliTool.decode(value)));
                  },
                  itemLabel: (value) => cliDisplayName(
                    cliRegistry.tryGet(CliTool.decode(value))!,
                    l10n,
                  ),
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledStackedRow(
                title: l10n.provider,
                body: AppDropdownField<String>(
                  items: providerIds,
                  initialItem: prov.isEmpty ? null : prov,
                  hintText: l10n.selectProvider,
                  decoration: dropdownDeco,
                  onChanged: (value) async {
                    final newProv = value ?? '';
                    var newModel = agent.model;
                    AppProviderConfig? nextProvider;
                    for (final p
                        in context.read<AppProviderCubit>().state.providersFor(
                          catalogCli,
                        )) {
                      if (p.id == newProv) {
                        nextProvider = p;
                        break;
                      }
                    }
                    if (nextProvider != null &&
                        isOfficialClaudeProvider(nextProvider)) {
                      newModel = '';
                    } else {
                      final defaultModel =
                          nextProvider?.defaultModel.trim() ?? '';
                      final names = _modelNamesForClaudeProvider(
                        providerId: newProv,
                        appProvider: nextProvider,
                        currentModel: agent.model,
                      );
                      if (!names.contains(newModel)) {
                        newModel = defaultModel.isNotEmpty ? defaultModel : '';
                      }
                    }
                    await _updateAgent(
                      agent.copyWith(provider: newProv, model: newModel),
                    );
                  },
                  itemLabel: (value) => providerLabels[value] ?? value,
                ),
                showDividerBelow: true,
              ),
              if (!hideModelPicker)
                SettingsLabeledStackedRow(
                  title: l10n.model,
                  body: AppDropdownField<String>(
                    items: modelNames,
                    initialItem: agent.model.isEmpty ? null : agent.model,
                    hintText: l10n.selectModel,
                    decoration: dropdownDeco,
                    onChanged: (value) =>
                        _updateAgent(agent.copyWith(model: value ?? '')),
                    itemLabel: (value) => value,
                  ),
                  showDividerBelow: true,
                ),
              SettingsLabeledStackedRow(
                title: l10n.agent,
                subtitle: l10n.agentBuiltInSubtitle,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDropdownField<String>(
                      key: ValueKey(
                        'project-agent-dd-${profile.projectId}-${agent.agent}-${_userAgentIds.join(",")}',
                      ),
                      items: FlashskyaiAgentCatalog.dropdownValues(
                        userAgentIds: _userAgentIds,
                      ),
                      initialItem: FlashskyaiAgentCatalog.activeDropdownValue(
                        agent.agent,
                        userAgentIds: _userAgentIds,
                      ),
                      hintText: l10n.selectAgent,
                      decoration: dropdownDeco,
                      headerMaxLines: 2,
                      listItemMaxLines: 2,
                      itemLabel: (value) => memberAgentDropdownItemLabel(
                        context,
                        l10n,
                        value,
                        userAgentIds: _userAgentIds,
                      ),
                      onChanged: (value) async {
                        final v =
                            value ?? FlashskyaiAgentCatalog.noneDropdownValue;
                        if (v == FlashskyaiAgentCatalog.noneDropdownValue) {
                          _agentCtl.clear();
                          await _updateAgent(agent.copyWith(agent: ''));
                        } else if (v ==
                            FlashskyaiAgentCatalog.customDropdownValue) {
                          final current = agent.agent.trim();
                          final next =
                              FlashskyaiAgentCatalog.isKnownAgentId(
                                current,
                                userAgentIds: _userAgentIds,
                              )
                              ? ''
                              : current;
                          _agentCtl.text = next;
                          await _updateAgent(agent.copyWith(agent: next));
                        } else {
                          _agentCtl.text = v;
                          await _updateAgent(agent.copyWith(agent: v));
                        }
                      },
                    ),
                    if (showCustomAgentField) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _agentCtl,
                        decoration: InputDecoration(
                          hintText: l10n.agentCustomIdHint,
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                        ),
                        onChanged: (v) => _updateAgent(agent.copyWith(agent: v)),
                      ),
                    ],
                  ],
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledRow(
                title: l10n.memberDangerouslySkipPermissions,
                subtitle: l10n.memberDangerouslySkipPermissionsHint,
                trailing: Switch(
                  value: agent.dangerouslySkipPermissions,
                  onChanged: (v) => _updateAgent(
                    agent.copyWith(dangerouslySkipPermissions: v),
                  ),
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledStackedRow(
                title: l10n.memberExtraArgs,
                body: TextField(
                  controller: _argsCtl,
                  decoration: const InputDecoration(),
                  onChanged: (v) => _updateAgent(agent.copyWith(extraArgs: v)),
                ),
                showDividerBelow: true,
              ),
              SettingsLabeledStackedRow(
                title: l10n.prompt,
                subtitle: l10n.memberPromptSubtitle,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final preset in TeamMemberPromptPreset.all)
                          ActionChip(
                            label: Text(
                              teamMemberPromptPresetLabel(l10n, preset.id),
                              style: AppTextStyles.of(context).bodySmall,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            onPressed: () => _applyPromptPreset(preset.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _promptCtl,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(),
                      onChanged: (v) => _updateAgent(agent.copyWith(prompt: v)),
                    ),
                  ],
                ),
                showDividerBelow: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
