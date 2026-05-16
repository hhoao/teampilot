import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/flashskyai_built_in_agents.dart';
import '../cubits/llm_config_cubit.dart';
import '../cubits/skill_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/skill.dart';
import '../models/team_config.dart';
import '../utils/app_keys.dart';
import '../widgets/app_outline_text_field.dart';
import '../widgets/dropdown/flashsky_dropdown_field.dart';
import '../widgets/dropdown/flashskyai_dropdown_decoration.dart';

enum _TeamPageSection { team, skills, members }

String _teamLoopChoiceLabel(AppLocalizations l10n, String? key) {
  switch (key) {
    case 'true':
      return l10n.teamLoopTrue;
    case 'false':
      return l10n.teamLoopFalse;
    case '__default__':
    default:
      return l10n.teamLoopDefault;
  }
}

String _memberAgentDropdownItemLabel(
  BuildContext context,
  AppLocalizations l10n,
  String value,
) {
  if (value == FlashskyBuiltInAgents.noneDropdownValue) {
    return l10n.agentBuiltInNone;
  }
  if (value == FlashskyBuiltInAgents.customDropdownValue) {
    return l10n.agentBuiltInCustom;
  }
  final ent = FlashskyBuiltInAgents.tryParseBuiltinId(value);
  if (ent != null) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final hint = zh ? ent.modelHintZh : ent.modelHintEn;
    return '${ent.id} · $hint';
  }
  return value;
}

class TeamConfigPage extends StatefulWidget {
  const TeamConfigPage({super.key});

  @override
  State<TeamConfigPage> createState() => _TeamConfigPageState();
}

class _TeamConfigPageState extends State<TeamConfigPage> {
  _TeamPageSection _section = _TeamPageSection.team;
  String? _selectedMemberId;

  String? _effectiveMemberId(TeamConfig team) {
    if (_section != _TeamPageSection.members) return null;
    if (team.members.isEmpty) return null;
    final sid = _selectedMemberId;
    if (sid != null && team.members.any((m) => m.id == sid)) return sid;
    return team.members.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final memberId = _effectiveMemberId(team);

    return Container(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBar(
            title: l10n.teamConfig,
            subtitle: l10n.teamSettingsSubtitle,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 820;
                final navWidth = 220.0;
                final contentPadding = compact
                    ? const EdgeInsets.fromLTRB(16, 20, 16, 16)
                    : const EdgeInsets.fromLTRB(24, 28, 28, 24);
                final bodyPaneWidth = constraints.maxWidth - navWidth - 1;
                final teamBodyMaxWidth =
                    (bodyPaneWidth - contentPadding.horizontal).clamp(
                      480.0,
                      3200.0,
                    );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: navWidth,
                      child: _NavPanel(
                        team: team,
                        section: _section,
                        selectedMemberId: memberId,
                        onSelect: (s) => setState(() => _section = s),
                        onSelectMember: (id) =>
                            setState(() => _selectedMemberId = id),
                        onAddMember: () async {
                          await teamCubit.addMember();
                          final t = teamCubit.state.selectedTeam;
                          if (t != null && t.members.isNotEmpty) {
                            setState(
                              () => _selectedMemberId = t.members.last.id,
                            );
                          }
                        },
                        l10n: l10n,
                      ),
                    ),
                    Container(
                      width: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    Expanded(
                      child: Padding(
                        padding: contentPadding,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: teamBodyMaxWidth,
                            ),
                            child: switch (_section) {
                              _TeamPageSection.team => _TeamInfoSection(
                                team: team,
                                cubit: teamCubit,
                              ),
                              _TeamPageSection.skills => _TeamSkillsSection(
                                team: team,
                                cubit: teamCubit,
                              ),
                              _TeamPageSection.members => _MemberDetailSection(
                                team: team,
                                cubit: teamCubit,
                                selectedMemberId: memberId,
                              ),
                            },
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

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 42, 40, 28),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
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

class _NavPanel extends StatelessWidget {
  const _NavPanel({
    required this.team,
    required this.section,
    required this.selectedMemberId,
    required this.onSelect,
    required this.onSelectMember,
    required this.onAddMember,
    required this.l10n,
  });

  final TeamConfig team;
  final _TeamPageSection section;
  final String? selectedMemberId;
  final ValueChanged<_TeamPageSection> onSelect;
  final ValueChanged<String> onSelectMember;
  final VoidCallback onAddMember;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(24, 28, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _NavItem(
            title: l10n.teamSettings,
            icon: Icons.groups_outlined,
            selected: section == _TeamPageSection.team,
            onTap: () => onSelect(_TeamPageSection.team),
          ),
          _NavItem(
            title: l10n.teamSkillsNav,
            icon: Icons.extension_outlined,
            selected: section == _TeamPageSection.skills,
            onTap: () => onSelect(_TeamPageSection.skills),
          ),
          _NavItem(
            title: l10n.members,
            icon: Icons.person_outline,
            selected: section == _TeamPageSection.members,
            trailingIcon: section == _TeamPageSection.members
                ? Icons.expand_less
                : Icons.expand_more,
            onTap: () => onSelect(_TeamPageSection.members),
          ),
          if (section == _TeamPageSection.members) ...[
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(left: 14, right: 2),
                children: [
                  for (final m in team.members)
                    _MemberNavSubItem(
                      member: m,
                      selected: m.id == selectedMemberId,
                      onTap: () => onSelectMember(m.id),
                    ),
                  _MemberNavAddTile(l10n: l10n, onTap: onAddMember),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberNavSubItem extends StatelessWidget {
  const _MemberNavSubItem({
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final TeamMemberConfig member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.64);
    final label = member.name.trim().isEmpty
        ? l10n.memberName
        : member.name.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 19,
                    color: selected ? textBase : muted,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
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

class _MemberNavAddTile extends StatelessWidget {
  const _MemberNavAddTile({required this.l10n, required this.onTap});

  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.72);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: DottedBorderContainer(
            color: cs.outlineVariant,
            radius: 10,
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 19, color: muted),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${l10n.add} ${l10n.memberName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.trailingIcon,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.64);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(icon, color: selected ? textBase : muted, size: 21),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 6),
                    Icon(
                      trailingIcon,
                      color: selected ? textBase : muted,
                      size: 24,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: textBase,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 13,
              color: textBase.withValues(alpha: 0.64),
            ),
          ),
        ],
      ],
    );
    if (trailing == null) return titleWidget;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleWidget),
        trailing!,
      ],
    );
  }
}

class _TeamSkillsSection extends StatelessWidget {
  const _TeamSkillsSection({required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final skillState = context.watch<SkillCubit>().state;
    final syncing = context.watch<TeamCubit>().state.isSyncingSkills;
    final enabled = skillState.installed
        .where((s) => s.enabled)
        .toList(growable: false);
    final assignedCount = enabled
        .where((s) => team.skillIds.contains(s.id))
        .length;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  title: l10n.teamSkillsAssignedCount(
                    assignedCount,
                    enabled.length,
                  ),
                  trailing: OutlinedButton.icon(
                    onPressed: () => context.go('/skills'),
                    icon: const Icon(Icons.extension_outlined, size: 16),
                    label: Text(l10n.teamSkillsManage),
                  ),
                ),
                if (syncing) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 14),
                if (enabled.isEmpty)
                  _TeamSkillsEmptyBlock(
                    textBase: textBase,
                    onGoSkills: () => context.go('/skills'),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final skill in enabled)
                        _TeamSkillRow(
                          skill: skill,
                          assigned: team.skillIds.contains(skill.id),
                          onAssignedChanged: (assigned) {
                            final ids = List<String>.from(team.skillIds);
                            if (assigned) {
                              if (!ids.contains(skill.id)) ids.add(skill.id);
                            } else {
                              ids.remove(skill.id);
                            }
                            cubit.updateSelected(team.copyWith(skillIds: ids));
                          },
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

class _TeamSkillsEmptyBlock extends StatelessWidget {
  const _TeamSkillsEmptyBlock({
    required this.textBase,
    required this.onGoSkills,
  });

  final Color textBase;
  final VoidCallback onGoSkills;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 36,
            color: textBase.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.skillsNoInstalled,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textBase,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.skillsNoInstalledHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: textBase.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onGoSkills,
            icon: const Icon(Icons.extension_outlined, size: 16),
            label: Text(l10n.teamSkillsManage),
          ),
        ],
      ),
    );
  }
}

class _TeamSkillRow extends StatelessWidget {
  const _TeamSkillRow({
    required this.skill,
    required this.assigned,
    required this.onAssignedChanged,
  });

  final Skill skill;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final sourceLabel = skill.repoOwner != null && skill.repoName != null
        ? '${skill.repoOwner}/${skill.repoName}'
        : l10n.skillsLocal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
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
                          skill.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: textBase,
                          ),
                        ),
                      ),
                      if (skill.readmeUrl != null) ...[
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _openSkillUrl(skill.readmeUrl!),
                          child: Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: textBase.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: textBase.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  if (skill.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      skill.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: textBase.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}

Future<void> _openSkillUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _TeamInfoSection extends StatefulWidget {
  const _TeamInfoSection({required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  @override
  State<_TeamInfoSection> createState() => _TeamInfoSectionState();
}

class _TeamInfoSectionState extends State<_TeamInfoSection> {
  late TextEditingController _nameCtl;
  late TextEditingController _argsCtl;
  late String _trackedTeamId;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.team.name);
    _argsCtl = TextEditingController(text: widget.team.extraArgs);
    _trackedTeamId = widget.team.id;
  }

  @override
  void didUpdateWidget(covariant _TeamInfoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.team.id != _trackedTeamId) {
      _trackedTeamId = widget.team.id;
      _nameCtl.text = widget.team.name;
      _argsCtl.text = widget.team.extraArgs;
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _argsCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  title: l10n.teamSettings,
                  subtitle: l10n.editTeamSubtitle,
                ),
                const SizedBox(height: 18),
                _FieldLabel(text: l10n.teamName),
                const SizedBox(height: 6),
                AppOutlineTextField(
                  controller: _nameCtl,
                  onChanged: (v) => widget.cubit.updateSelected(
                    widget.team.copyWith(name: v),
                  ),
                ),
                const SizedBox(height: 14),
                _FieldLabel(text: l10n.teamLoop),
                const SizedBox(height: 6),
                FlashskyDropdownField<String>(
                  key: ValueKey(
                    'team-loop-${widget.team.id}-${widget.team.loop ?? 'nil'}',
                  ),
                  items: const ['__default__', 'true', 'false'],
                  initialItem: widget.team.loop == null
                      ? '__default__'
                      : (widget.team.loop! ? 'true' : 'false'),
                  hintText: l10n.teamLoopDefault,
                  decoration: FlashskyDropdownDecorations.denseField(context),
                  overlayHeight: 200,
                  listItemMaxLines: 2,
                  itemLabel: (k) => _teamLoopChoiceLabel(l10n, k),
                  onChanged: (value) {
                    final key = value ?? '__default__';
                    final bool? next = key == '__default__'
                        ? null
                        : key == 'true';
                    widget.cubit.updateSelected(
                      widget.team.copyWith(loop: next, updateLoop: true),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.teamLoopSubtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: textBase.withValues(alpha: 0.58),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                _FieldLabel(text: l10n.teamExtraArgs),
                const SizedBox(height: 6),
                AppOutlineTextField(
                  controller: _argsCtl,
                  hintText: l10n.teamExtraArgsHint,
                  onChanged: (v) => widget.cubit.updateSelected(
                    widget.team.copyWith(extraArgs: v),
                  ),
                ),
              ],
            ),
          ),
          _DangerZone(team: widget.team, cubit: widget.cubit),
        ],
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteTeam),
        content: Text(l10n.deleteTeamConfirm(team.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await cubit.deleteSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorColor = Theme.of(context).colorScheme.error;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            title: l10n.dangerZone,
            subtitle: l10n.deleteTeamSubtitle,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: AppKeys.deleteButton,
              onPressed: () => _confirmDelete(context),
              icon: Icon(Icons.delete_outline, size: 18, color: errorColor),
              label: Text(l10n.deleteTeam, style: TextStyle(color: errorColor)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: errorColor.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: textBase.withValues(alpha: 0.7),
      ),
    );
  }
}

class _MemberDetailSection extends StatelessWidget {
  const _MemberDetailSection({
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
          style: TextStyle(
            fontSize: 14,
            color: textBase.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    final canDelete = team.members.length > 1;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    member.name.trim().isEmpty ? l10n.memberName : member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: textBase,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.delete,
                  onPressed: canDelete
                      ? () => cubit.deleteMember(member.id)
                      : null,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
          ),
          _Card(
            child: _MemberConfigForm(
              key: ValueKey(member.id),
              member: member,
              cubit: cubit,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberConfigForm extends StatefulWidget {
  const _MemberConfigForm({
    super.key,
    required this.member,
    required this.cubit,
  });

  final TeamMemberConfig member;
  final TeamCubit cubit;

  @override
  State<_MemberConfigForm> createState() => _MemberConfigFormState();
}

class _MemberConfigFormState extends State<_MemberConfigForm> {
  late TextEditingController _nameCtl;
  late TextEditingController _agentCtl;
  late TextEditingController _argsCtl;
  late TextEditingController _promptCtl;

  @override
  void initState() {
    super.initState();
    _syncControllers(widget.member);
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = widget.member;
    final llmState = context.watch<LlmConfigCubit>().state;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    final providerNames = llmState.config.providers.keys.toList()..sort();
    final prov = m.provider;
    if (prov.trim().isNotEmpty && !providerNames.contains(prov)) {
      providerNames.add(prov);
    }

    final modelNames =
        llmState.config.models.values
            .where((model) => prov.isEmpty || model.provider == prov)
            .map((model) => model.name)
            .toList()
          ..sort();
    final model = m.model;
    if (model.trim().isNotEmpty && !modelNames.contains(model)) {
      modelNames.add(model);
    }

    final dropdownDeco = FlashskyDropdownDecorations.denseField(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardHeader(title: l10n.configure, subtitle: l10n.editMemberSubtitle),
        const SizedBox(height: 18),
        _FieldLabel(text: l10n.memberName),
        const SizedBox(height: 6),
        AppOutlineTextField(
          controller: _nameCtl,
          onChanged: (v) => _update(m.copyWith(name: v)),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.provider),
        const SizedBox(height: 6),
        FlashskyDropdownField<String>(
          items: providerNames,
          initialItem: prov.isEmpty ? null : prov,
          hintText: l10n.selectProvider,
          decoration: dropdownDeco,
          onChanged: (value) {
            final newProv = value ?? '';
            var newModel = m.model;
            final stillValid = llmState.config.models.values.any(
              (md) => md.name == newModel && md.provider == newProv,
            );
            if (!stillValid) newModel = '';
            _update(m.copyWith(provider: newProv, model: newModel));
          },
          itemLabel: (value) => value,
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.model),
        const SizedBox(height: 6),
        FlashskyDropdownField<String>(
          items: modelNames,
          initialItem: model.isEmpty ? null : model,
          hintText: l10n.selectModel,
          decoration: dropdownDeco,
          onChanged: (value) => _update(m.copyWith(model: value ?? '')),
          itemLabel: (value) => value,
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.agent),
        const SizedBox(height: 4),
        Text(
          l10n.agentBuiltInSubtitle,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: textBase.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 8),
        FlashskyDropdownField<String>(
          key: ValueKey('member-agent-dd-${widget.member.id}-${m.agent}'),
          items: FlashskyBuiltInAgents.dropdownValues(),
          initialItem: FlashskyBuiltInAgents.activeDropdownValue(m.agent),
          hintText: l10n.selectAgent,
          decoration: dropdownDeco,
          headerMaxLines: 2,
          listItemMaxLines: 2,
          itemLabel: (value) =>
              _memberAgentDropdownItemLabel(context, l10n, value),
          onChanged: (value) {
            final v = value ?? FlashskyBuiltInAgents.noneDropdownValue;
            if (v == FlashskyBuiltInAgents.noneDropdownValue) {
              _agentCtl.clear();
              _update(m.copyWith(agent: ''));
            } else if (v == FlashskyBuiltInAgents.customDropdownValue) {
              final current = m.agent.trim();
              final next =
                  FlashskyBuiltInAgents.tryParseBuiltinId(current) == null
                  ? current
                  : '';
              _agentCtl.text = next;
              _update(m.copyWith(agent: next));
            } else {
              _agentCtl.text = v;
              _update(m.copyWith(agent: v));
            }
          },
        ),
        if (FlashskyBuiltInAgents.activeDropdownValue(m.agent) ==
            FlashskyBuiltInAgents.customDropdownValue) ...[
          const SizedBox(height: 8),
          AppOutlineTextField(
            controller: _agentCtl,
            hintText: l10n.agentCustomIdHint,
            onChanged: (v) => _update(m.copyWith(agent: v)),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.memberDangerouslySkipPermissions,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textBase,
            ),
          ),
          subtitle: Text(
            l10n.memberDangerouslySkipPermissionsHint,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: textBase.withValues(alpha: 0.62),
            ),
          ),
          value: m.dangerouslySkipPermissions,
          onChanged: (v) => _update(m.copyWith(dangerouslySkipPermissions: v)),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.memberExtraArgs),
        const SizedBox(height: 6),
        AppOutlineTextField(
          controller: _argsCtl,
          onChanged: (v) => _update(m.copyWith(extraArgs: v)),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.prompt),
        const SizedBox(height: 6),
        AppOutlineTextField(
          controller: _promptCtl,
          minLines: 3,
          maxLines: 6,
          onChanged: (v) => _update(m.copyWith(prompt: v)),
        ),
      ],
    );
  }
}

class DottedBorderContainer extends StatelessWidget {
  const DottedBorderContainer({
    required this.child,
    required this.color,
    required this.radius,
    super.key,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    const dashLength = 6.0;
    const gapLength = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0, metric.length);
        dashed.addPath(
          metric.extractPath(distance, next.toDouble()),
          Offset.zero,
        );
        distance = next + gapLength;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
