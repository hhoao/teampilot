import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/config_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/layout_preferences.dart';
import '../models/team_config.dart';
import '../services/launch_command_builder.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';
import '../utils/perf.dart';
import 'llm_config_workspace.dart';

class ConfigWorkspace extends StatelessWidget {
  const ConfigWorkspace({this.section, super.key});

  final ConfigSection? section;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final configCubit = context.watch<ConfigCubit>();
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (section != null && configCubit.state.section != section) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        configCubit.selectSection(section!);
      });
    }

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      key: AppKeys.configWorkspace,
      color: colors.workspaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsTitleBar(
            title: l10n.settings,
            subtitle: l10n.settingsPageSubtitle,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                final navWidth = compact ? 220.0 : 314.0;
                final contentPadding = compact
                    ? const EdgeInsets.fromLTRB(20, 24, 20, 20)
                    : const EdgeInsets.fromLTRB(36, 36, 44, 28);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: navWidth,
                      child: _ConfigNavPanel(
                        section: configCubit.state.section,
                        compact: compact,
                        onSelectSection: (s) {
                          FramePerf.mark('nav config ${s.name}');
                          context.read<ConfigCubit>().selectSection(s);
                          context.go('/config/${s.name}');
                        },
                        l10n: l10n,
                      ),
                    ),
                    Container(width: 1, color: colors.subtleBorder),
                    Expanded(
                      child: PipelinePerf(
                        label: 'config body ${configCubit.state.section.name}',
                        child: BuildPerf(
                          label: 'config ${configCubit.state.section.name}',
                          builder: (_) => Padding(
                            padding: contentPadding,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1120,
                                ),
                                child: switch (configCubit.state.section) {
                                  ConfigSection.team => TeamConfigWorkspace(
                                    team: team,
                                  ),
                                  ConfigSection.members =>
                                    MemberConfigWorkspace(team: team),
                                  ConfigSection.layout =>
                                    const LayoutConfigWorkspace(),
                                  ConfigSection.llm =>
                                    const LlmConfigWorkspace(),
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TeamConfigWorkspace extends StatefulWidget {
  const TeamConfigWorkspace({required this.team, super.key});

  final TeamConfig team;

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
          child: ListView.builder(
            itemCount: widget.team.members.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
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
                              prefixIcon: const Icon(
                                Icons.folder_open_outlined,
                              ),
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
                  ],
                );
              }
              final memberIndex = index - 1;
              return _LaunchOrderRow(
                index: memberIndex,
                team: widget.team,
                member: widget.team.members[memberIndex],
                controller: context.read<TeamCubit>(),
              );
            },
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
              context.read<TeamCubit>().state.statusMessage,
              style: TextStyle(color: textBase.withValues(alpha: 0.66)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _save() {
    return context.read<TeamCubit>().updateSelected(
      widget.team.copyWith(
        name: _nameController.text,
        workingDirectory: _directoryController.text,
        extraArgs: _extraArgsController.text,
      ),
    );
  }
}

class MemberConfigWorkspace extends StatefulWidget {
  const MemberConfigWorkspace({required this.team, super.key});

  final TeamConfig team;

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
      if (member.id == context.read<ConfigCubit>().state.selectedMemberId) {
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
    await context.read<TeamCubit>().updateMember(
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
  const LayoutConfigWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final layoutController = context.watch<LayoutCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WorkspaceHeading(
          title: l10n.layout,
          subtitle: l10n.layoutPageSubtitle,
        ),
        const SizedBox(height: 16),
        _LayoutControls(
          preferences: layoutController.state.preferences,
          controller: layoutController,
        ),
      ],
    );
  }
}

class _LayoutControls extends StatelessWidget {
  const _LayoutControls({required this.preferences, required this.controller});

  final LayoutPreferences preferences;
  final LayoutCubit controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
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
            const SizedBox(height: 14),
            _Section(
              title: l10n.appearance,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.theme,
                    style: TextStyle(
                      fontSize: 12,
                      color: textBase.withValues(alpha: 0.68),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        key: AppKeys.themeSystemButton,
                        onPressed: () => controller.setThemeMode('system'),
                        child: Text(l10n.themeSystem),
                      ),
                      OutlinedButton(
                        key: AppKeys.themeDarkButton,
                        onPressed: () => controller.setThemeMode('dark'),
                        child: Text(l10n.themeDark),
                      ),
                      OutlinedButton(
                        key: AppKeys.themeLightButton,
                        onPressed: () => controller.setThemeMode('light'),
                        child: Text(l10n.themeLight),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.language,
                    style: TextStyle(
                      fontSize: 12,
                      color: textBase.withValues(alpha: 0.68),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        key: AppKeys.languageEnButton,
                        onPressed: () => controller.setLocale('en'),
                        child: Text(l10n.languageEnglish),
                      ),
                      OutlinedButton(
                        key: AppKeys.languageZhButton,
                        onPressed: () => controller.setLocale('zh'),
                        child: Text(l10n.languageChinese),
                      ),
                    ],
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
    bool? contextSidebarVisible,
    bool? membersVisible,
    bool? fileTreeVisible,
  }) {
    controller.setRegionVisibility(
      appRailVisible: true,
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
  final TeamCubit controller;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
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
            child: Text(
              LaunchCommandBuilder.preview(team, member),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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

class _SettingsTitleBar extends StatelessWidget {
  const _SettingsTitleBar({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: colors.workspaceBackground,
        border: Border(bottom: BorderSide(color: colors.subtleBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textBase,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textBase.withValues(alpha: 0.66),
              fontSize: 14,
              height: 1.25,
            ),
          ),
        ],
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
            fontSize: 15,
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: textBase,
            ),
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

class _ConfigNavPanel extends StatelessWidget {
  const _ConfigNavPanel({
    required this.section,
    required this.compact,
    required this.onSelectSection,
    required this.l10n,
  });

  final ConfigSection section;
  final bool compact;
  final ValueChanged<ConfigSection> onSelectSection;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      color: colors.workspaceBackground,
      padding: compact
          ? const EdgeInsets.fromLTRB(14, 22, 12, 20)
          : const EdgeInsets.fromLTRB(24, 28, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConfigNavItem(
            key: AppKeys.configTeamSectionButton,
            title: l10n.teamSettings,
            icon: Icons.groups_2_outlined,
            compact: compact,
            selected: section == ConfigSection.team,
            onTap: () => onSelectSection(ConfigSection.team),
          ),
          _ConfigNavItem(
            key: AppKeys.configMembersSectionButton,
            title: l10n.members,
            icon: Icons.person_outline,
            compact: compact,
            selected: section == ConfigSection.members,
            onTap: () => onSelectSection(ConfigSection.members),
          ),
          _ConfigNavItem(
            key: AppKeys.configLlmSectionButton,
            title: l10n.llmConfig,
            icon: Icons.memory_outlined,
            compact: compact,
            selected: section == ConfigSection.llm,
            onTap: () => onSelectSection(ConfigSection.llm),
          ),
          _ConfigNavItem(
            key: AppKeys.configLayoutSectionButton,
            title: l10n.layout,
            icon: Icons.dashboard_customize_outlined,
            compact: compact,
            selected: section == ConfigSection.layout,
            onTap: () => onSelectSection(ConfigSection.layout),
          ),
        ],
      ),
    );
  }
}

class _ConfigNavItem extends StatelessWidget {
  const _ConfigNavItem({
    super.key,
    required this.title,
    required this.icon,
    required this.compact,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.64);
    final selectedColor = colors.selectedBackground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? selectedColor : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
              child: Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? textBase : muted,
                    size: compact ? 21 : 23,
                  ),
                  SizedBox(width: compact ? 12 : 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected ? textBase : muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
