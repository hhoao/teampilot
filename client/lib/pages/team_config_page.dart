import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/config_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/team_config.dart';
import '../services/launch_command_builder.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';

enum _TeamPageSection { team, members }

class TeamConfigPage extends StatefulWidget {
  const TeamConfigPage({super.key});

  @override
  State<TeamConfigPage> createState() => _TeamConfigPageState();
}

class _TeamConfigPageState extends State<TeamConfigPage> {
  var _section = _TeamPageSection.team;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final compact = false;
    final navWidth = 220.0;
    final contentPadding = const EdgeInsets.fromLTRB(36, 36, 44, 28);

    return Container(
      key: AppKeys.teamConfigWorkspace,
      color: colors.workspaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBar(
            title: l10n.teamConfig,
            subtitle: l10n.editTeamSubtitle,
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: navWidth,
                  child: _TeamConfigNavPanel(
                    section: _section,
                    compact: compact,
                    onSelectSection: (s) => setState(() => _section = s),
                    l10n: l10n,
                  ),
                ),
                Container(width: 1, color: colors.subtleBorder),
                Expanded(
                  child: Padding(
                    padding: contentPadding,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: switch (_section) {
                          _TeamPageSection.team =>
                            _TeamConfigForm(team: team),
                          _TeamPageSection.members =>
                            _MemberConfigForm(team: team),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamConfigForm extends StatefulWidget {
  const _TeamConfigForm({required this.team});

  final TeamConfig team;

  @override
  State<_TeamConfigForm> createState() => _TeamConfigFormState();
}

class _TeamConfigFormState extends State<_TeamConfigForm> {
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
  void didUpdateWidget(covariant _TeamConfigForm oldWidget) {
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(title: l10n.teamSettings, subtitle: l10n.editTeamSubtitle),
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

class _MemberConfigForm extends StatefulWidget {
  const _MemberConfigForm({required this.team});

  final TeamConfig team;

  @override
  State<_MemberConfigForm> createState() => _MemberConfigFormState();
}

class _MemberConfigFormState extends State<_MemberConfigForm> {
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
  void didUpdateWidget(covariant _MemberConfigForm oldWidget) {
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
        _Heading(
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

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title, required this.subtitle});

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

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});

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

class _SizedField extends StatelessWidget {
  const _SizedField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 360, child: child);
  }
}

class _TeamConfigNavPanel extends StatelessWidget {
  const _TeamConfigNavPanel({
    required this.section,
    required this.compact,
    required this.onSelectSection,
    required this.l10n,
  });

  final _TeamPageSection section;
  final bool compact;
  final ValueChanged<_TeamPageSection> onSelectSection;
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
          _TeamConfigNavItem(
            title: l10n.teamSettings,
            icon: Icons.groups_2_outlined,
            compact: compact,
            selected: section == _TeamPageSection.team,
            onTap: () => onSelectSection(_TeamPageSection.team),
          ),
          _TeamConfigNavItem(
            title: l10n.members,
            icon: Icons.person_outline,
            compact: compact,
            selected: section == _TeamPageSection.members,
            onTap: () => onSelectSection(_TeamPageSection.members),
          ),
        ],
      ),
    );
  }
}

class _TeamConfigNavItem extends StatelessWidget {
  const _TeamConfigNavItem({
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
                  Icon(icon, color: selected ? textBase : muted, size: compact ? 21 : 23),
                  SizedBox(width: compact ? 12 : 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
