import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../models/team_config.dart';
import '../../models/team_member_prompt_presets.dart';
import '../../services/app/flashskyai_agent_catalog_service.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../services/provider/claude/claude_official_provider.dart';
import '../../services/storage/storage_resolver.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/app_provider_model_candidates.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/team_member_naming.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import '../../widgets/team/team_lead_badge.dart';
import 'team_config_helpers.dart';
import 'team_config_member_dialogs.dart';

class TeamMemberDetailSection extends StatelessWidget {
  const TeamMemberDetailSection({
    super.key,
    required this.team,
    required this.cubit,
    required this.selectedMemberId,
  });

  final TeamConfig team;
  final TeamCubit cubit;
  final String? selectedMemberId;

  TeamMemberConfig? _memberOrNull() {
    final id = selectedMemberId;
    if (id == null || team.members.isEmpty) return null;
    for (final m in team.members) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final member = _memberOrNull();
    if (member == null) {
      return Center(
        child: Text(
          l10n.openMember,
          textAlign: TextAlign.center,
          style: AppTextStyles.of(
            context,
          ).body.copyWith(color: textBase.withValues(alpha: 0.55)),
        ),
      );
    }

    return SingleChildScrollView(
      child: TeamMemberConfigForm(
        key: ValueKey(member.id),
        team: team,
        member: member,
        cubit: cubit,
      ),
    );
  }
}

class TeamMemberConfigForm extends StatefulWidget {
  const TeamMemberConfigForm({
    super.key,
    required this.team,
    required this.member,
    required this.cubit,
  });

  final TeamConfig team;
  final TeamMemberConfig member;
  final TeamCubit cubit;

  @override
  State<TeamMemberConfigForm> createState() => TeamMemberConfigFormState();
}

class TeamMemberConfigFormState extends State<TeamMemberConfigForm> {
  late TextEditingController _nameCtl;
  late TextEditingController _agentCtl;
  late TextEditingController _argsCtl;
  late TextEditingController _promptCtl;
  List<String> _userAgentIds = const [];

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.member);
    _loadUserAgents();
  }

  Future<void> _loadUserAgents() async {
    final storageRoots = context.read<StorageRoots>();
    final ids = await FlashskyaiAgentCatalogService(
      storageRoots: storageRoots,
    ).listUserAgentIds();
    if (!mounted) return;
    setState(() => _userAgentIds = ids);
  }

  void _syncControllers(TeamMemberConfig m) {
    _nameCtl = TextEditingController(text: m.name);
    _agentCtl = TextEditingController(text: m.agent);
    _argsCtl = TextEditingController(text: m.extraArgs);
    _promptCtl = TextEditingController(text: m.prompt);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _agentCtl.dispose();
    _argsCtl.dispose();
    _promptCtl.dispose();
    super.dispose();
  }

  void _update(TeamMemberConfig next) {
    widget.cubit.updateMember(widget.member.id, next);
  }

  void _applyPromptPreset(String presetId) {
    final l10n = context.l10n;
    final text = teamMemberPromptPresetText(l10n, presetId);
    if (text.isEmpty) return;
    _promptCtl.text = text;
    _promptCtl.selection = TextSelection.collapsed(offset: text.length);
    _update(widget.member.copyWith(prompt: text));
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
    final m = widget.member;
    final memberCatalogCli =
        catalogCliForTeam(context, widget.member.cli ?? widget.team.cli) ??
        CliTool.claude;
    final dropdownDeco = AppDropdownDecorations.themed(context);

    final prov = m.provider;
    final appProviders = context
        .watch<AppProviderCubit>()
        .state
        .providersFor(memberCatalogCli)
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
        memberCatalogCli,
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
        currentModel: m.model,
      ),
    )..sort();
    final model = m.model;
    final hideModelPicker =
        catalogCliForTeam(context, widget.member.cli ?? widget.team.cli) ==
            CliTool.claude &&
        selectedAppProvider != null &&
        isOfficialClaudeProvider(selectedAppProvider);
    final cliRegistry = CliToolRegistryScope.of(context);

    final showCustomAgentField =
        FlashskyaiAgentCatalog.activeDropdownValue(
          m.agent,
          userAgentIds: _userAgentIds,
        ) ==
        FlashskyaiAgentCatalog.customDropdownValue;

    final canDelete =
        widget.team.members.length > 1 && !TeamMemberNaming.isTeamLead(m);
    final errorColor = Theme.of(context).colorScheme.error;

    Widget agentBody() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDropdownField<String>(
          key: ValueKey(
            'member-agent-dd-${widget.member.id}-${m.agent}-${_userAgentIds.join(",")}',
          ),
          items: FlashskyaiAgentCatalog.dropdownValues(
            userAgentIds: _userAgentIds,
          ),
          initialItem: FlashskyaiAgentCatalog.activeDropdownValue(
            m.agent,
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
          onChanged: (value) {
            final v = value ?? FlashskyaiAgentCatalog.noneDropdownValue;
            if (v == FlashskyaiAgentCatalog.noneDropdownValue) {
              _agentCtl.clear();
              _update(m.copyWith(agent: ''));
            } else if (v == FlashskyaiAgentCatalog.customDropdownValue) {
              final current = m.agent.trim();
              final next =
                  FlashskyaiAgentCatalog.isKnownAgentId(
                    current,
                    userAgentIds: _userAgentIds,
                  )
                  ? ''
                  : current;
              _agentCtl.text = next;
              _update(m.copyWith(agent: next));
            } else {
              _agentCtl.text = v;
              _update(m.copyWith(agent: v));
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
            onChanged: (v) => _update(m.copyWith(agent: v)),
          ),
        ],
      ],
    );

    return SettingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsLabeledStackedRow(
            title: l10n.memberName,
            subtitle: l10n.memberNameSubtitle,
            titleTrailing: TeamMemberNaming.isTeamLead(m) || canDelete
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (TeamMemberNaming.isTeamLead(m)) const TeamLeadBadge(),
                      if (canDelete)
                        IconButton(
                          tooltip: l10n.delete,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: throttledAsync(
                            'team_delete_member_${m.id}',
                            () => confirmDeleteTeamMember(
                              context,
                              widget.cubit,
                              m,
                              l10n,
                            ),
                          ),
                          icon: Icon(
                            Icons.delete_outline,
                            size: AppIconSizes.md,
                            color: errorColor,
                          ),
                        ),
                    ],
                  )
                : null,
            body: TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(),
              onChanged: (v) => _update(m.copyWith(name: v)),
            ),
            showDividerBelow: true,
          ),
          if (widget.team.teamMode == TeamMode.mixed)
            SettingsLabeledStackedRow(
              title: l10n.teamCliLabel,
              body: AppDropdownField<String>(
                items: [
                  for (final def in cliRegistry.launchable) def.id.value,
                ],
                initialItem: widget.member.cli?.value,
                hintText: l10n.memberCliInheritHint,
                decoration: dropdownDeco,
                onChanged: (value) {
                  _update(
                    widget.member.copyWith(
                      cli: value == null ? null : CliTool.decode(value),
                      updateCli: true,
                    ),
                  );
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
              onChanged: (value) {
                final newProv = value ?? '';
                var newModel = m.model;
                AppProviderConfig? nextProvider;
                for (final p
                    in context.read<AppProviderCubit>().state.providersFor(
                      memberCatalogCli,
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
                  final defaultModel = nextProvider?.defaultModel.trim() ?? '';
                  final names = _modelNamesForClaudeProvider(
                    providerId: newProv,
                    appProvider: nextProvider,
                    currentModel: m.model,
                  );
                  final stillValid = names.contains(newModel);
                  if (!stillValid) {
                    newModel = defaultModel.isNotEmpty ? defaultModel : '';
                  }
                }
                _update(m.copyWith(provider: newProv, model: newModel));
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
                initialItem: model.isEmpty ? null : model,
                hintText: l10n.selectModel,
                decoration: dropdownDeco,
                onChanged: (value) => _update(m.copyWith(model: value ?? '')),
                itemLabel: (value) => value,
              ),
              showDividerBelow: true,
            ),
          SettingsLabeledStackedRow(
            title: l10n.agent,
            subtitle: l10n.agentBuiltInSubtitle,
            body: agentBody(),
            showDividerBelow: true,
          ),
          SettingsLabeledRow(
            title: l10n.memberDangerouslySkipPermissions,
            subtitle: l10n.memberDangerouslySkipPermissionsHint,
            trailing: Switch(
              value: m.dangerouslySkipPermissions,
              onChanged: (v) =>
                  _update(m.copyWith(dangerouslySkipPermissions: v)),
            ),
            showDividerBelow: true,
          ),
          SettingsLabeledStackedRow(
            title: l10n.memberExtraArgs,
            body: TextField(
              controller: _argsCtl,
              decoration: const InputDecoration(),
              onChanged: (v) => _update(m.copyWith(extraArgs: v)),
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
                  onChanged: (v) => _update(m.copyWith(prompt: v)),
                ),
              ],
            ),
            showDividerBelow: false,
          ),
        ],
      ),
    );
  }
}
