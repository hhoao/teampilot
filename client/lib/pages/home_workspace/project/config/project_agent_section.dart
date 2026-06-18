import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/cli_presets_cubit.dart';
import '../../../../cubits/identity_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/cli_preset.dart';
import '../../../../models/personal_identity.dart';
import '../../../../models/project_agent_config.dart';
import '../../../../models/project_agent_prompt_presets.dart';
import '../../../../models/team_config.dart';
import '../../../../services/app/flashskyai_agent_catalog_service.dart';
import '../../../../services/cli/registry/cli_display_name.dart';
import '../../../../services/cli/registry/cli_tool_registry.dart';
import '../../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../../services/storage/storage_resolver.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../../widgets/cli/member_agent_preset_field.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import 'cli_presets_manage_dialog.dart';

const _kAgentCardGap = 12.0;

/// Personal-project agent + CLI defaults (backed by [IdentityCubit]).
class ProjectAgentSection extends StatelessWidget {
  const ProjectAgentSection({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final personal = context.watch<IdentityCubit>().activePersonal;
    if (personal == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ProjectAgentConfigForm(
      key: ValueKey(personal.id),
      personal: personal,
      cubit: context.read<IdentityCubit>(),
    );
  }
}

class ProjectAgentConfigForm extends StatefulWidget {
  const ProjectAgentConfigForm({
    super.key,
    required this.personal,
    required this.cubit,
  });

  final PersonalIdentity personal;
  final IdentityCubit cubit;

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
    final agent = widget.personal.agent;
    _agentCtl = TextEditingController(text: agent.agent);
    _argsCtl = TextEditingController(text: agent.extraArgs);
    _promptCtl = TextEditingController(text: agent.prompt);
    _loadUserAgents();
  }

  @override
  void didUpdateWidget(covariant ProjectAgentConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.personal.id != widget.personal.id ||
        oldWidget.personal.agent != widget.personal.agent) {
      _syncControllers(widget.personal.agent);
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
    if (_agentCtl.text != agent.agent) {
      _agentCtl.text = agent.agent;
    }
    if (_argsCtl.text != agent.extraArgs) {
      _argsCtl.text = agent.extraArgs;
    }
    if (_promptCtl.text != agent.prompt) {
      _promptCtl.text = agent.prompt;
    }
  }

  @override
  void dispose() {
    _agentCtl.dispose();
    _argsCtl.dispose();
    _promptCtl.dispose();
    super.dispose();
  }

  Future<void> _updateAgent(ProjectAgentConfig next) async {
    await widget.cubit.updateActivePersonalAgent(next);
  }

  void _applyPromptPreset(String presetId) {
    final l10n = context.l10n;
    final text = projectAgentPromptPresetText(l10n, presetId);
    if (text.isEmpty) return;
    _promptCtl.text = text;
    _promptCtl.selection = TextSelection.collapsed(offset: text.length);
    unawaited(_updateAgent(widget.personal.agent.copyWith(prompt: text)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final personal = widget.personal;
    final agent = personal.agent;
    final cliRegistry = CliToolRegistryScope.of(context);
    final presetsCubit = context.read<CliPresetsCubit>();
    final activePreset =
        presetsCubit.state.presetById(personal.activePresetId ?? '');
    final effectiveCli = activePreset?.cli ?? CliTool.claude;
    final showAgentPreset = cliRegistry.supportsMemberAgentPreset(effectiveCli);
    final agentPresetStyle = cliRegistry.memberAgentPresetStyle(effectiveCli);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PresetInfoRow(personal: personal),
          const SizedBox(height: _kAgentCardGap),
          SettingsSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroupHeader(title: l10n.homeWorkspaceProjectAgent),
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
                  title: l10n.prompt,
                  subtitle: l10n.projectAgentPromptSubtitle,
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final preset in ProjectAgentPromptPreset.all)
                            ActionChip(
                              label: Text(
                                projectAgentPromptPresetLabel(l10n, preset.id),
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
                        onChanged: (v) =>
                            _updateAgent(agent.copyWith(prompt: v)),
                      ),
                    ],
                  ),
                  showDividerBelow: true,
                ),
                SettingsAdvancedExpansion(
                  title: l10n.workspaceAdvancedSettings,
                  subtitle: l10n.projectAdvancedSettingsSubtitle,
                  children: [
                    if (showAgentPreset && agentPresetStyle != null)
                      SettingsLabeledStackedRow(
                        title: l10n.agent,
                        subtitle: memberAgentPresetSubtitle(
                          l10n,
                          agentPresetStyle,
                        ),
                        body: MemberAgentPresetField(
                          cli: effectiveCli,
                          agent: agent.agent,
                          userAgentIds: _userAgentIds,
                          customAgentController: _agentCtl,
                          fieldKeyPrefix: 'project-${personal.id}',
                          onAgentChanged: (value) =>
                              _updateAgent(agent.copyWith(agent: value)),
                        ),
                        showDividerBelow: true,
                      ),
                    SettingsLabeledStackedRow(
                      title: l10n.projectAgentExtraArgs,
                      subtitle: l10n.projectAgentExtraArgsSubtitle,
                      body: TextField(
                        controller: _argsCtl,
                        decoration: const InputDecoration(),
                        onChanged: (v) =>
                            _updateAgent(agent.copyWith(extraArgs: v)),
                      ),
                      showDividerBelow: false,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetInfoRow extends StatelessWidget {
  const _PresetInfoRow({required this.personal});

  final PersonalIdentity personal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final presetsCubit = context.watch<CliPresetsCubit>();
    final preset = presetsCubit.state.presetById(personal.activePresetId ?? '');
    final registry = CliToolRegistryScope.of(context);

    return SettingsSurfaceCard(
      child: SettingsLabeledRow(
        title: l10n.projectCliPresetLabel,
        subtitle: preset != null
            ? _presetSubtitle(preset, registry, l10n)
            : l10n.projectCliNoPresetHint,
        trailing: TextButton(
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (_) => const CliPresetsManageDialog(),
            );
          },
          child: Text(l10n.projectCliManagePresets),
        ),
        showDividerBelow: false,
      ),
    );
  }

  String _presetSubtitle(CliPreset preset, CliToolRegistry registry, AppLocalizations l10n) {
    final def = registry.tryGet(preset.cli);
    final cliName = def != null ? cliDisplayName(def, l10n) : preset.cli.value;
    return cliName;
  }
}
