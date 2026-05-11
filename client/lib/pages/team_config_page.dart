import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/team_config.dart';
import '../services/launch_command_builder.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';

class TeamConfigPage extends StatelessWidget {
  const TeamConfigPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(36, 36, 44, 28),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: _TeamConfigForm(team: team),
                ),
              ),
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
