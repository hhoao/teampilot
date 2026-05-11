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
      color: colors.workspaceBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBar(title: l10n.teamConfig, subtitle: l10n.teamSettingsSubtitle),
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
                        section: _section,
                        compact: compact,
                        onSelect: (s) => setState(() => _section = s),
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
                                  team: team, cubit: teamCubit),
                              _TeamPageSection.members => _MembersSection(
                                  team: team, cubit: teamCubit),
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
    required this.section,
    required this.compact,
    required this.onSelect,
    required this.l10n,
  });

  final _TeamPageSection section;
  final bool compact;
  final ValueChanged<_TeamPageSection> onSelect;
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
        ],
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

class _MembersSection extends StatelessWidget {
  const _MembersSection({required this.team, required this.cubit});

  final TeamConfig team;
  final TeamCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.members,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: textBase,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${team.members.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: textBase.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final member in team.members)
            _MemberCard(
              member: member,
              canDelete: team.members.length > 1,
              onEdit: () => _openEditor(context, member),
              onDelete: () => cubit.deleteMember(member.id),
            ),
          _AddMemberCard(onTap: () => _openEditor(context, null)),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    TeamMemberConfig? existing,
  ) async {
    final result = await showDialog<TeamMemberConfig>(
      context: context,
      builder: (_) => _MemberEditorDialog(member: existing),
    );
    if (result == null) return;
    if (existing == null) {
      await cubit.addMember();
      final added = cubit.state.selectedTeam?.members.last;
      if (added != null) {
        await cubit.updateMember(added.id, result.copyWith(id: added.id));
      }
    } else {
      await cubit.updateMember(existing.id, result);
    }
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final TeamMemberConfig member;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final muted = textBase.withValues(alpha: 0.66);

    final details = <String>[
      if (member.provider.trim().isNotEmpty) member.provider.trim(),
      if (member.model.trim().isNotEmpty) member.model.trim(),
      if (member.agent.trim().isNotEmpty) member.agent.trim(),
    ].join(' · ');

    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.typeBadgeAccountBg,
              border: Border.all(color: colors.typeBadgeAccountBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.person_outline,
              size: 20,
              color: colors.typeBadgeAccountText,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name.isEmpty ? l10n.memberName : member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textBase,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.edit,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
          IconButton(
            tooltip: l10n.delete,
            onPressed: canDelete ? onDelete : null,
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
    );
  }
}

class _AddMemberCard extends StatelessWidget {
  const _AddMemberCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: DottedBorderContainer(
            color: colors.border,
            radius: 12,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 20,
                      color: textBase.withValues(alpha: 0.78),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '${l10n.add} ${l10n.memberName}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textBase.withValues(alpha: 0.85),
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
        dashed.addPath(metric.extractPath(distance, next.toDouble()),
            Offset.zero);
        distance = next + gapLength;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _MemberEditorDialog extends StatefulWidget {
  const _MemberEditorDialog({required this.member});

  final TeamMemberConfig? member;

  @override
  State<_MemberEditorDialog> createState() => _MemberEditorDialogState();
}

class _MemberEditorDialogState extends State<_MemberEditorDialog> {
  late TextEditingController _nameCtl;
  late TextEditingController _agentCtl;
  late TextEditingController _argsCtl;
  late TextEditingController _promptCtl;
  String _provider = '';
  String _model = '';

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _nameCtl = TextEditingController(text: m?.name ?? '');
    _agentCtl = TextEditingController(text: m?.agent ?? '');
    _argsCtl = TextEditingController(text: m?.extraArgs ?? '');
    _promptCtl = TextEditingController(text: m?.prompt ?? '');
    _provider = m?.provider ?? '';
    _model = m?.model ?? '';
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _agentCtl.dispose();
    _argsCtl.dispose();
    _promptCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isEditing = widget.member != null;
    final llmState = context.watch<LlmConfigCubit>().state;

    final providerNames = llmState.config.providers.keys.toList()..sort();
    if (_provider.isNotEmpty && !providerNames.contains(_provider)) {
      providerNames.add(_provider);
    }

    final modelNames = llmState.config.models.values
        .where((m) => _provider.isEmpty || m.provider == _provider)
        .map((m) => m.name)
        .toList()
      ..sort();
    if (_model.isNotEmpty && !modelNames.contains(_model)) {
      modelNames.add(_model);
    }

    return Dialog(
      backgroundColor: colors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  title: isEditing ? l10n.edit : l10n.add,
                  subtitle: l10n.editMemberSubtitle,
                ),
                const SizedBox(height: 18),
                _FieldLabel(text: l10n.memberName),
                const SizedBox(height: 6),
                TextField(controller: _nameCtl),
                const SizedBox(height: 12),
                _FieldLabel(text: l10n.provider),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _provider.isEmpty ? null : _provider,
                  isExpanded: true,
                  hint: Text(l10n.selectProvider),
                  items: [
                    for (final name in providerNames)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _provider = value ?? '';
                      final stillValid = llmState.config.models.values.any(
                        (m) => m.name == _model && m.provider == _provider,
                      );
                      if (!stillValid) _model = '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                _FieldLabel(text: l10n.model),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _model.isEmpty ? null : _model,
                  isExpanded: true,
                  hint: Text(l10n.selectModel),
                  items: [
                    for (final name in modelNames)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) => setState(() => _model = value ?? ''),
                ),
                const SizedBox(height: 12),
                _FieldLabel(text: l10n.agent),
                const SizedBox(height: 6),
                TextField(controller: _agentCtl),
                const SizedBox(height: 12),
                _FieldLabel(text: l10n.memberExtraArgs),
                const SizedBox(height: 6),
                TextField(controller: _argsCtl),
                const SizedBox(height: 12),
                _FieldLabel(text: l10n.prompt),
                const SizedBox(height: 6),
                TextField(
                  controller: _promptCtl,
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final base = widget.member ??
                            const TeamMemberConfig(id: '', name: '');
                        Navigator.of(context).pop(
                          base.copyWith(
                            name: _nameCtl.text,
                            provider: _provider,
                            model: _model,
                            agent: _agentCtl.text,
                            extraArgs: _argsCtl.text,
                            prompt: _promptCtl.text,
                          ),
                        );
                      },
                      child: Text(isEditing ? l10n.save : l10n.add),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
