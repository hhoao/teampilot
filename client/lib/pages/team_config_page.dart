import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/llm_config_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/team_config.dart';
import '../theme/app_theme.dart';

enum _TeamPageSection { team, members }

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
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final team = teamCubit.state.selectedTeam;

    if (team == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final memberId = _effectiveMemberId(team);

    return Container(
      color: colors.workspaceBackground,
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
                final navWidth = compact ? 220.0 : 280.0;
                final contentPadding = compact
                    ? const EdgeInsets.fromLTRB(20, 24, 20, 20)
                    : const EdgeInsets.fromLTRB(36, 32, 44, 28);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: navWidth,
                      child: _NavPanel(
                        team: team,
                        section: _section,
                        compact: compact,
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
                    Container(width: 1, color: colors.subtleBorder),
                    Expanded(
                      child: Padding(
                        padding: contentPadding,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1120),
                            child: switch (_section) {
                              _TeamPageSection.team => _TeamInfoSection(
                                team: team,
                                cubit: teamCubit,
                              ),
                              _TeamPageSection.members =>
                                _MemberDetailSection(
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

class _NavPanel extends StatelessWidget {
  const _NavPanel({
    required this.team,
    required this.section,
    required this.compact,
    required this.selectedMemberId,
    required this.onSelect,
    required this.onSelectMember,
    required this.onAddMember,
    required this.l10n,
  });

  final TeamConfig team;
  final _TeamPageSection section;
  final bool compact;
  final String? selectedMemberId;
  final ValueChanged<_TeamPageSection> onSelect;
  final ValueChanged<String> onSelectMember;
  final VoidCallback onAddMember;
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
          _NavItem(
            title: l10n.teamSettings,
            icon: Icons.groups_outlined,
            compact: compact,
            selected: section == _TeamPageSection.team,
            onTap: () => onSelect(_TeamPageSection.team),
          ),
          _NavItem(
            title: l10n.members,
            icon: Icons.person_outline,
            compact: compact,
            selected: section == _TeamPageSection.members,
            onTap: () => onSelect(_TeamPageSection.members),
          ),
          if (section == _TeamPageSection.members) ...[
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(left: compact ? 10 : 14, right: 2),
                children: [
                  for (final m in team.members)
                    _MemberNavSubItem(
                      member: m,
                      compact: compact,
                      selected: m.id == selectedMemberId,
                      onTap: () => onSelectMember(m.id),
                    ),
                  _MemberNavAddTile(
                    compact: compact,
                    l10n: l10n,
                    onTap: onAddMember,
                  ),
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
    required this.compact,
    required this.selected,
    required this.onTap,
  });

  final TeamMemberConfig member;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.64);
    final label =
        member.name.trim().isEmpty ? l10n.memberName : member.name.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? colors.selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: compact ? 40 : 44,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: compact ? 18 : 19,
                    color: selected ? textBase : muted,
                  ),
                  SizedBox(width: compact ? 8 : 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
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
  const _MemberNavAddTile({
    required this.compact,
    required this.l10n,
    required this.onTap,
  });

  final bool compact;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
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
            color: colors.border,
            radius: 10,
            child: SizedBox(
              height: compact ? 40 : 44,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
                child: Row(
                  children: [
                    Icon(Icons.add, size: compact ? 18 : 19, color: muted),
                    SizedBox(width: compact ? 8 : 10),
                    Expanded(
                      child: Text(
                        compact
                            ? l10n.add
                            : '${l10n.add} ${l10n.memberName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? colors.selectedBackground : Colors.transparent,
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

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Column(
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
                TextField(
                  controller: _nameCtl,
                  onChanged: (v) => widget.cubit.updateSelected(
                    widget.team.copyWith(name: v),
                  ),
                ),
                const SizedBox(height: 14),
                _FieldLabel(text: l10n.teamExtraArgs),
                const SizedBox(height: 6),
                TextField(
                  controller: _argsCtl,
                  decoration: InputDecoration(hintText: l10n.teamExtraArgsHint),
                  onChanged: (v) => widget.cubit.updateSelected(
                    widget.team.copyWith(extraArgs: v),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CardHeader(
          title: l10n.configure,
          subtitle: l10n.editMemberSubtitle,
        ),
        const SizedBox(height: 18),
        _FieldLabel(text: l10n.memberName),
        const SizedBox(height: 6),
        TextField(
          controller: _nameCtl,
          onChanged: (v) => _update(m.copyWith(name: v)),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.provider),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: prov.isEmpty ? null : prov,
          isExpanded: true,
          hint: Text(l10n.selectProvider),
          items: [
            for (final name in providerNames)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (value) {
            final newProv = value ?? '';
            var newModel = m.model;
            final stillValid = llmState.config.models.values.any(
              (md) => md.name == newModel && md.provider == newProv,
            );
            if (!stillValid) newModel = '';
            _update(m.copyWith(provider: newProv, model: newModel));
          },
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.model),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: model.isEmpty ? null : model,
          isExpanded: true,
          hint: Text(l10n.selectModel),
          items: [
            for (final name in modelNames)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (value) => _update(m.copyWith(model: value ?? '')),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.agent),
        const SizedBox(height: 6),
        TextField(
          controller: _agentCtl,
          onChanged: (v) => _update(m.copyWith(agent: v)),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.memberExtraArgs),
        const SizedBox(height: 6),
        TextField(
          controller: _argsCtl,
          onChanged: (v) => _update(m.copyWith(extraArgs: v)),
        ),
        const SizedBox(height: 12),
        _FieldLabel(text: l10n.prompt),
        const SizedBox(height: 6),
        TextField(
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
