import 'package:flutter/material.dart';

import '../utils/app_keys.dart';
import '../controllers/config_controller.dart';
import '../l10n/app_localizations.dart';
import '../services/launch_command_builder.dart';
import '../controllers/layout_controller.dart';
import '../models/layout_preferences.dart';
import '../controllers/llm_config_controller.dart';
import '../models/team_config.dart';
import '../controllers/team_controller.dart';
import '../theme/app_theme.dart';
import 'llm_config_workspace.dart';

class ConfigWorkspace extends StatelessWidget {
  const ConfigWorkspace({
    required this.configController,
    required this.layoutController,
    required this.llmConfigController,
    required this.teamController,
    super.key,
  });

  final ConfigController configController;
  final LayoutController layoutController;
  final LlmConfigController llmConfigController;
  final TeamController teamController;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final team = teamController.selectedTeam;
    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      key: AppKeys.configWorkspace,
      color: colors.workspaceBackground,
      padding: const EdgeInsets.all(16),
      child: switch (configController.section) {
        ConfigSection.team => TeamConfigWorkspace(
          team: team,
          controller: teamController,
        ),
        ConfigSection.members => MemberConfigWorkspace(
          team: team,
          teamController: teamController,
          configController: configController,
        ),
        ConfigSection.layout => LayoutConfigWorkspace(
          layoutController: layoutController,
        ),
        ConfigSection.llm => LlmConfigWorkspace(
          controller: llmConfigController,
        ),
      },
    );
  }
}


class TeamConfigWorkspace extends StatefulWidget {
  const TeamConfigWorkspace({
    required this.team,
    required this.controller,
    super.key,
  });

  final TeamConfig team;
  final TeamController controller;

  @override
  State<TeamConfigWorkspace> createState() => _TeamConfigWorkspaceState();
}

class _TeamConfigWorkspaceState extends State<TeamConfigWorkspace> {
  late final TextEditingController _nameController;
  late final TextEditingController _directoryController;
  late final TextEditingController _extraArgsController;
  String _teamId = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _directoryController = TextEditingController();
    _extraArgsController = TextEditingController();
    _syncFromTeam();
  }

  @override
  void didUpdateWidget(covariant TeamConfigWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.team.id != _teamId) {
      _syncFromTeam();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _directoryController.dispose();
    _extraArgsController.dispose();
    super.dispose();
  }

  void _syncFromTeam() {
    _teamId = widget.team.id;
    _nameController.text = widget.team.name;
    _directoryController.text = widget.team.workingDirectory;
    _extraArgsController.text = widget.team.extraArgs;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Column(
      key: AppKeys.teamConfigWorkspace,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorkspaceHeading(
          title: l10n.teamSettings,
          subtitle: l10n.editTeamSubtitle,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _SizedField(
                      child: TextField(
                        key: AppKeys.teamNameField,
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l10n.teamName,
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                      ),
                    ),
                    _SizedField(
                      child: TextField(
                        key: AppKeys.workingDirectoryField,
                        controller: _directoryController,
                        decoration: InputDecoration(
                          labelText: l10n.workingDirectory,
                          prefixIcon: const Icon(Icons.folder_open_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  key: AppKeys.extraArgsField,
                  controller: _extraArgsController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.teamExtraArgs,
                    hintText: l10n.teamExtraArgsHint,
                    prefixIcon: const Icon(Icons.terminal_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.memberLaunchOrder,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textBase,
                  ),
                ),
                const SizedBox(height: 10),
                for (var index = 0; index < widget.team.members.length; index++)
                  _LaunchOrderRow(
                    index: index,
                    team: widget.team,
                    member: widget.team.members[index],
                    controller: widget.controller,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              key: AppKeys.saveButton,
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.save),
            ),
            Text(
              widget.controller.statusMessage,
              style: TextStyle(color: textBase.withValues(alpha: 0.66)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() {
    return widget.controller.updateSelected(
      widget.team.copyWith(
        name: _nameController.text,
        workingDirectory: _directoryController.text,
        extraArgs: _extraArgsController.text,
      ),
    );
  }
}

class MemberConfigWorkspace extends StatefulWidget {
  const MemberConfigWorkspace({
    required this.team,
    required this.teamController,
    required this.configController,
    super.key,
  });

  final TeamConfig team;
  final TeamController teamController;
  final ConfigController configController;

  @override
  State<MemberConfigWorkspace> createState() => _MemberConfigWorkspaceState();
}

class _MemberConfigWorkspaceState extends State<MemberConfigWorkspace> {
  late final TextEditingController _nameController;
  late final TextEditingController _providerController;
  late final TextEditingController _modelController;
  late final TextEditingController _agentController;
  late final TextEditingController _extraArgsController;
  String _memberId = '';
  String _validationMessage = '';

  TeamMemberConfig get _member {
    for (final member in widget.team.members) {
      if (member.id == widget.configController.selectedMemberId) {
        return member;
      }
    }
    return widget.team.members.first;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _providerController = TextEditingController();
    _modelController = TextEditingController();
    _agentController = TextEditingController();
    _extraArgsController = TextEditingController();
    _syncFromMember();
  }

  @override
  void didUpdateWidget(covariant MemberConfigWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_member.id != _memberId) {
      _syncFromMember();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _providerController.dispose();
    _modelController.dispose();
    _agentController.dispose();
    _extraArgsController.dispose();
    super.dispose();
  }

  void _syncFromMember() {
    final member = _member;
    _memberId = member.id;
    _nameController.text = member.name;
    _providerController.text = member.provider;
    _modelController.text = member.model;
    _agentController.text = member.agent;
    _extraArgsController.text = member.extraArgs;
    _validationMessage = '';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final member = _member;
    final draft = member.copyWith(
      name: _nameController.text,
      provider: _providerController.text,
      model: _modelController.text,
      agent: _agentController.text,
      extraArgs: _extraArgsController.text,
    );
    final previewTeam = widget.team.copyWith(
      members: [
        for (final item in widget.team.members)
          if (item.id == member.id) draft else item,
      ],
    );

    return Column(
      key: AppKeys.memberConfigWorkspace,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorkspaceHeading(
          title: member.name,
          subtitle: l10n.editMemberSubtitle,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _SizedField(
                      child: TextField(
                        key: AppKeys.memberNameField(member.id),
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: l10n.memberName,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    _SizedField(
                      child: TextField(
                        key: AppKeys.memberProviderField(member.id),
                        controller: _providerController,
                        decoration: InputDecoration(
                          labelText: l10n.provider,
                          prefixIcon: const Icon(Icons.hub_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    _SizedField(
                      child: TextField(
                        key: AppKeys.memberModelField(member.id),
                        controller: _modelController,
                        decoration: InputDecoration(
                          labelText: l10n.model,
                          prefixIcon: const Icon(Icons.memory_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    _SizedField(
                      child: TextField(
                        key: AppKeys.memberAgentField(member.id),
                        controller: _agentController,
                        decoration: InputDecoration(
                          labelText: l10n.agent,
                          prefixIcon: const Icon(Icons.badge_outlined),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  key: AppKeys.memberExtraArgsField(member.id),
                  controller: _extraArgsController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: l10n.memberExtraArgs,
                    prefixIcon: const Icon(Icons.tune_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (member.name == 'team-lead') ...[
                  const SizedBox(height: 12),
                  _TeamLeadNotice(),
                ],
                if (_validationMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _validationMessage,
                    key: AppKeys.memberConfigValidationMessage,
                    style: const TextStyle(color: Color(0xFFFFB4AB)),
                  ),
                ],
                const SizedBox(height: 16),
                SelectableText(
                  key: AppKeys.memberConfigCommandPreview,
                  LaunchCommandBuilder.preview(previewTeam, draft),
                  style: TextStyle(
                    color: textBase.withValues(alpha: 0.68),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: AppKeys.memberConfigSaveButton,
          onPressed: () => _save(member),
          icon: const Icon(Icons.save_outlined),
          label: Text(l10n.saveMember),
        ),
      ],
    );
  }

  Future<void> _save(TeamMemberConfig member) async {
    if (member.name == 'team-lead' &&
        _nameController.text.trim() != 'team-lead') {
      setState(() {
        _validationMessage = context.l10n.teamLeadNameRequired;
      });
      return;
    }
    await widget.teamController.updateMember(
      member.id,
      member.copyWith(
        name: _nameController.text,
        provider: _providerController.text,
        model: _modelController.text,
        agent: _agentController.text,
        extraArgs: _extraArgsController.text,
      ),
    );
    setState(() {
      _validationMessage = '';
    });
  }
}

class LayoutConfigWorkspace extends StatelessWidget {
  const LayoutConfigWorkspace({required this.layoutController, super.key});

  final LayoutController layoutController;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorkspaceHeading(
          title: l10n.layout,
          subtitle: l10n.layoutPageSubtitle,
        ),
        const SizedBox(height: 16),
        _LayoutControls(preferences: layoutController.preferences, controller: layoutController),
      ],
    );
  }
}

class _LayoutControls extends StatelessWidget {
  const _LayoutControls({required this.preferences, required this.controller});

  final LayoutPreferences preferences;
  final LayoutController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Expanded(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
              title: l10n.toolPlacement,
              child: SegmentedButton<ToolPanelPlacement>(
                segments: [
                  ButtonSegment(
                    value: ToolPanelPlacement.right,
                    label: Text(l10n.right),
                    icon: const Icon(Icons.vertical_split_outlined),
                  ),
                  ButtonSegment(
                    value: ToolPanelPlacement.bottom,
                    label: Text(l10n.bottom),
                    icon: const Icon(Icons.splitscreen_outlined),
                  ),
                ],
                selected: {preferences.toolPlacement},
                onSelectionChanged: (selection) =>
                    controller.setToolPlacement(selection.single),
                multiSelectionEnabled: false,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  key: AppKeys.toolPlacementRightButton,
                  onPressed: () =>
                      controller.setToolPlacement(ToolPanelPlacement.right),
                  child: Text(l10n.rightTools),
                ),
                OutlinedButton(
                  key: AppKeys.toolPlacementBottomButton,
                  onPressed: () =>
                      controller.setToolPlacement(ToolPanelPlacement.bottom),
                  child: Text(l10n.bottomTray),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Section(
              title: l10n.membersAndFileTree,
              child: SegmentedButton<ToolsArrangement>(
                segments: [
                  ButtonSegment(
                    value: ToolsArrangement.stacked,
                    label: Text(l10n.stacked),
                    icon: const Icon(Icons.view_agenda_outlined),
                  ),
                  ButtonSegment(
                    value: ToolsArrangement.tabs,
                    label: Text(l10n.tabs),
                    icon: const Icon(Icons.tab_outlined),
                  ),
                ],
                selected: {preferences.toolsArrangement},
                onSelectionChanged: (selection) =>
                    controller.setToolsArrangement(selection.single),
                multiSelectionEnabled: false,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  key: AppKeys.toolsArrangementStackedButton,
                  onPressed: () =>
                      controller.setToolsArrangement(ToolsArrangement.stacked),
                  child: Text(l10n.stackedTools),
                ),
                OutlinedButton(
                  key: AppKeys.toolsArrangementTabsButton,
                  onPressed: () =>
                      controller.setToolsArrangement(ToolsArrangement.tabs),
                  child: Text(l10n.tabbedTools),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _Section(
              title: l10n.regionVisibility,
              child: Column(
                children: [
                  SwitchListTile(
                    key: AppKeys.appRailVisibilitySwitch,
                    title: Text(l10n.appRail),
                    value: preferences.appRailVisible,
                    onChanged: (value) => _setVisibility(appRailVisible: value),
                  ),
                  SwitchListTile(
                    key: AppKeys.contextSidebarVisibilitySwitch,
                    title: Text(l10n.teamSessions),
                    value: preferences.contextSidebarVisible,
                    onChanged: (value) =>
                        _setVisibility(contextSidebarVisible: value),
                  ),
                  SwitchListTile(
                    key: AppKeys.membersVisibilitySwitch,
                    title: Text(l10n.members),
                    value: preferences.membersVisible,
                    onChanged: (value) => _setVisibility(membersVisible: value),
                  ),
                  SwitchListTile(
                    key: AppKeys.fileTreeVisibilitySwitch,
                    title: Text(l10n.fileTree),
                    value: preferences.fileTreeVisible,
                    onChanged: (value) =>
                        _setVisibility(fileTreeVisible: value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setVisibility({
    bool? appRailVisible,
    bool? contextSidebarVisible,
    bool? membersVisible,
    bool? fileTreeVisible,
  }) {
    controller.setRegionVisibility(
      appRailVisible: appRailVisible ?? preferences.appRailVisible,
      contextSidebarVisible:
          contextSidebarVisible ?? preferences.contextSidebarVisible,
      membersVisible: membersVisible ?? preferences.membersVisible,
      fileTreeVisible: fileTreeVisible ?? preferences.fileTreeVisible,
    );
  }
}

class _LaunchOrderRow extends StatelessWidget {
  const _LaunchOrderRow({
    required this.index,
    required this.team,
    required this.member,
    required this.controller,
  });

  final int index;
  final TeamConfig team;
  final TeamMemberConfig member;
  final TeamController controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text('${index + 1}')),
          Expanded(child: Text(member.name)),
          IconButton(
            key: AppKeys.memberOpenButton(member.id),
            tooltip: l10n.openMember,
            onPressed: () => controller.launchMember(member.id),
            icon: const Icon(Icons.open_in_new),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SelectableText(
              LaunchCommandBuilder.preview(team, member),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamLeadNotice extends StatelessWidget {
  const _TeamLeadNotice();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.warningBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.warningBorder),
      ),
      child: Text(
        l10n.teamLeadNotice,
        style: TextStyle(color: colors.warningText),
      ),
    );
  }
}

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
    return SizedBox(width: 360, child: child);
  }
}
