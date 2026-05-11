import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cubits/skill_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/skill.dart';
import '../theme/app_theme.dart';

enum SkillSection { installed, discovery, repos, backups }

class SkillManagementPage extends StatefulWidget {
  const SkillManagementPage({super.key});

  @override
  State<SkillManagementPage> createState() => _SkillManagementPageState();
}

class _SkillManagementPageState extends State<SkillManagementPage> {
  SkillSection _section = SkillSection.installed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return BlocConsumer<SkillCubit, SkillState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            duration: const Duration(seconds: 4),
          ),
        );
        context.read<SkillCubit>().clearError();
      },
      builder: (context, state) {
        return Container(
          color: colors.workspaceBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TitleBar(
                title: l10n.skillsTitle,
                subtitle: l10n.skillsSubtitle,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 820;
                    final navWidth = compact ? 220.0 : 280.0;
                    final padding = compact
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
                            l10n: l10n,
                            onSelect: (s) => setState(() => _section = s),
                          ),
                        ),
                        Container(width: 1, color: colors.subtleBorder),
                        Expanded(
                          child: Padding(
                            padding: padding,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1120,
                                ),
                                child: switch (_section) {
                                  SkillSection.installed => _InstalledSection(
                                    state: state,
                                    onGoDiscovery: () => setState(
                                      () => _section = SkillSection.discovery,
                                    ),
                                  ),
                                  SkillSection.discovery => _DiscoverySection(
                                    state: state,
                                    onGoRepos: () => setState(
                                      () => _section = SkillSection.repos,
                                    ),
                                  ),
                                  SkillSection.repos => _ReposSection(
                                    state: state,
                                  ),
                                  SkillSection.backups => _BackupsSection(
                                    state: state,
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
      },
    );
  }
}

// ============================================================================
// Shared chrome (titlebar / nav)
// ============================================================================

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
    required this.l10n,
    required this.onSelect,
  });

  final SkillSection section;
  final bool compact;
  final AppLocalizations l10n;
  final ValueChanged<SkillSection> onSelect;

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
            title: l10n.skillsNavInstalled,
            icon: Icons.inventory_2_outlined,
            compact: compact,
            selected: section == SkillSection.installed,
            onTap: () => onSelect(SkillSection.installed),
          ),
          _NavItem(
            title: l10n.skillsNavDiscovery,
            icon: Icons.travel_explore_outlined,
            compact: compact,
            selected: section == SkillSection.discovery,
            onTap: () => onSelect(SkillSection.discovery),
          ),
          _NavItem(
            title: l10n.skillsNavRepos,
            icon: Icons.source_outlined,
            compact: compact,
            selected: section == SkillSection.repos,
            onTap: () => onSelect(SkillSection.repos),
          ),
          _NavItem(
            title: l10n.skillsNavBackups,
            icon: Icons.history,
            compact: compact,
            selected: section == SkillSection.backups,
            onTap: () => onSelect(SkillSection.backups),
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
  const _CardHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: textBase,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
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

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final l10n = context.l10n;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ============================================================================
// Installed section
// ============================================================================

class _InstalledSection extends StatelessWidget {
  const _InstalledSection({required this.state, required this.onGoDiscovery});
  final SkillState state;
  final VoidCallback onGoDiscovery;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SkillCubit>();
    final updates = {for (final u in state.updates) u.id: u};

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(
                  title: l10n.skillsInstalledCount(state.installed.length),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (state.updates.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: cubit.updateAll,
                          icon: const Icon(Icons.upgrade, size: 16),
                          label: Text(l10n.skillsUpdateAll(state.updates.length)),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _onImportFromDisk(context),
                        icon: const Icon(Icons.folder_open_outlined, size: 16),
                        label: Text(l10n.skillsImportFromDisk),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _onInstallZip(context),
                        icon: const Icon(Icons.archive_outlined, size: 16),
                        label: Text(l10n.skillsInstallFromZip),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.updatesLoading
                            ? null
                            : cubit.checkUpdates,
                        icon: state.updatesLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 16),
                        label: Text(
                          state.updatesLoading
                              ? l10n.skillsCheckingUpdates
                              : l10n.skillsCheckUpdates,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (state.installed.isEmpty)
                  _EmptyBlock(
                    icon: Icons.inventory_2_outlined,
                    title: l10n.skillsNoInstalled,
                    hint: l10n.skillsNoInstalledHint,
                    actionLabel: l10n.skillsGoDiscovery,
                    onAction: onGoDiscovery,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in state.installed)
                        _InstalledSkillRow(
                          skill: s,
                          updateInfo: updates[s.id],
                          busy: state.busyIds.contains(s.id),
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

  Future<void> _onInstallZip(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;
    await context.read<SkillCubit>().installFromZip(File(path));
  }

  Future<void> _onImportFromDisk(BuildContext context) async {
    final cubit = context.read<SkillCubit>();
    final l10n = context.l10n;
    final scanned = await cubit.scanUnmanaged();
    if (!context.mounted) return;
    if (scanned.isEmpty) {
      _showSnack(context, l10n.skillsImportNothing);
      return;
    }
    final selected = await showDialog<List<UnmanagedSkill>>(
      context: context,
      builder: (_) => _ImportUnmanagedDialog(skills: scanned),
    );
    if (selected == null || selected.isEmpty) return;
    if (!context.mounted) return;
    await context.read<SkillCubit>().importUnmanaged(selected);
  }
}

class _InstalledSkillRow extends StatelessWidget {
  const _InstalledSkillRow({
    required this.skill,
    this.updateInfo,
    this.busy = false,
  });
  final Skill skill;
  final SkillUpdateInfo? updateInfo;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final cubit = context.read<SkillCubit>();
    final hasUpdate = updateInfo != null;
    final sourceLabel = skill.repoOwner != null && skill.repoName != null
        ? '${skill.repoOwner}/${skill.repoName}'
        : l10n.skillsLocal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
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
                          onTap: () => _openUrl(skill.readmeUrl!),
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
                      if (hasUpdate) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.skillsUpdateAvailable,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
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
            Switch(
              value: skill.enabled,
              onChanged: (v) => cubit.toggleSkillEnabled(skill, v),
            ),
            if (hasUpdate)
              IconButton(
                tooltip: l10n.skillsCardUpdate,
                onPressed: busy ? null : () => cubit.updateSkill(skill),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upgrade, size: 18),
              ),
            IconButton(
              tooltip: l10n.skillsCardUninstall,
              onPressed: busy
                  ? null
                  : () => _onUninstall(context, skill),
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onUninstall(BuildContext context, Skill s) async {
    final l10n = context.l10n;
    final ok = await _confirm(
      context,
      title: l10n.skillsCardUninstall,
      message: l10n.skillsUninstallConfirm(s.name),
      confirmLabel: l10n.skillsCardUninstall,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await context.read<SkillCubit>().uninstall(s);
    if (!context.mounted) return;
    _showSnack(context, l10n.skillsUninstallSuccess(s.name));
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 36, color: textBase.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textBase,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: textBase.withValues(alpha: 0.55),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ImportUnmanagedDialog extends StatefulWidget {
  const _ImportUnmanagedDialog({required this.skills});
  final List<UnmanagedSkill> skills;

  @override
  State<_ImportUnmanagedDialog> createState() => _ImportUnmanagedDialogState();
}

class _ImportUnmanagedDialogState extends State<_ImportUnmanagedDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.skills.map((s) => s.directory).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.skillsImportTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.skills.length,
                  itemBuilder: (context, i) {
                    final s = widget.skills[i];
                    final checked = _selected.contains(s.directory);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setState(() {
                          if (v ?? false) {
                            _selected.add(s.directory);
                          } else {
                            _selected.remove(s.directory);
                          }
                        });
                      },
                      title: Text(s.name),
                      subtitle: Text(
                        s.description ?? s.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final selected = widget.skills
                                .where((s) => _selected.contains(s.directory))
                                .toList();
                            Navigator.of(context).pop(selected);
                          },
                    child: Text(l10n.skillsImportSelected(_selected.length)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Discovery section
// ============================================================================

enum _SearchSource { repos, skillsSh }

class _DiscoverySection extends StatefulWidget {
  const _DiscoverySection({required this.state, required this.onGoRepos});
  final SkillState state;
  final VoidCallback onGoRepos;

  @override
  State<_DiscoverySection> createState() => _DiscoverySectionState();
}

class _DiscoverySectionState extends State<_DiscoverySection> {
  _SearchSource _source = _SearchSource.repos;
  String _searchQuery = '';
  String _filterRepo = 'all';
  String _filterStatus = 'all';
  final _skillsShCtl = TextEditingController();
  static const _pageSize = 30;

  late final PagingController<int, DiscoverableSkill> _pagingController;
  SkillState? _lastState;

  Set<String> _installedKeys(SkillState s) => s.installed
      .map((sk) => '${sk.directory.toLowerCase()}:${(sk.repoOwner ?? '').toLowerCase()}:${(sk.repoName ?? '').toLowerCase()}')
      .toSet();

  @override
  void initState() {
    super.initState();
    _pagingController = PagingController<int, DiscoverableSkill>(
      getNextPageKey: (s) {
        final allItems = (s.pages ?? const []).expand((p) => p).toList();
        return allItems.length;
      },
      fetchPage: (pageKey) {
        final ik = _installedKeys(widget.state);
        final all = _filtered(ik);
        final start = pageKey;
        final end = (start + _pageSize).clamp(0, all.length);
        if (start >= all.length) return const [];
        return all.sublist(start, end);
      },
    );
    _lastState = widget.state;
  }

  @override
  void didUpdateWidget(covariant _DiscoverySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.discoverable != _lastState?.discoverable ||
        oldWidget.state != widget.state) {
      _lastState = widget.state;
      _pagingController.refresh();
    }
  }

  @override
  void dispose() {
    _pagingController.dispose();
    _skillsShCtl.dispose();
    super.dispose();
  }

  List<DiscoverableSkill> _filtered(Set<String> installedKeys) {
    return widget.state.discoverable.where((d) {
      if (_filterRepo != 'all') {
        if ('${d.repoOwner}/${d.repoName}' != _filterRepo) return false;
      }
      final installKey =
          '${d.directory.split('/').last.toLowerCase()}:${d.repoOwner.toLowerCase()}:${d.repoName.toLowerCase()}';
      final installed = installedKeys.contains(installKey);
      if (_filterStatus == 'installed' && !installed) return false;
      if (_filterStatus == 'uninstalled' && installed) return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return d.name.toLowerCase().contains(q) ||
          '${d.repoOwner}/${d.repoName}'.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final cubit = context.read<SkillCubit>();
    final installedKeys = state.installed
        .map((s) => '${s.directory.toLowerCase()}:${(s.repoOwner ?? '').toLowerCase()}:${(s.repoName ?? '').toLowerCase()}')
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _SourceToggle(
                    label: l10n.skillsSourceRepos,
                    selected: _source == _SearchSource.repos,
                    onTap: () {
                      setState(() => _source = _SearchSource.repos);
                      _pagingController.refresh();
                    },
                  ),
                  const SizedBox(width: 8),
                  _SourceToggle(
                    label: l10n.skillsSourceSkillsSh,
                    selected: _source == _SearchSource.skillsSh,
                    onTap: () {
                      setState(() => _source = _SearchSource.skillsSh);
                      _pagingController.refresh();
                    },
                  ),
                  const Spacer(),
                  if (_source == _SearchSource.repos)
                    IconButton(
                      tooltip: l10n.skillsCheckUpdates,
                      onPressed: state.discoveryLoading
                          ? null
                          : cubit.refreshDiscoverable,
                      icon: state.discoveryLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (_source == _SearchSource.repos)
                _buildReposFilters(context, state)
              else
                _buildSkillsShInput(context, cubit, l10n),
            ],
          ),
        ),
        if (_source == _SearchSource.repos)
          _buildReposPagedGrid(context, state, installedKeys)
        else
          _buildSkillsShGrid(context, state, cubit, installedKeys),
      ],
    );
  }

  Widget _buildReposFilters(BuildContext context, SkillState state) {
    final l10n = context.l10n;
    final repoOptions = <String>{
      for (final d in state.discoverable) '${d.repoOwner}/${d.repoName}',
    }.toList()
      ..sort();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: l10n.skillsSearchPlaceholder,
              isDense: true,
            ),
            onChanged: (v) {
              setState(() => _searchQuery = v);
              _pagingController.refresh();
            },
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String>(
            initialValue: _filterRepo,
            isExpanded: true,
            items: [
              DropdownMenuItem(
                  value: 'all', child: Text(l10n.skillsFilterRepoAll)),
              for (final repo in repoOptions)
                DropdownMenuItem(
                    value: repo,
                    child: Text(repo, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              setState(() => _filterRepo = v ?? 'all');
              _pagingController.refresh();
            },
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String>(
            initialValue: _filterStatus,
            isExpanded: true,
            items: [
              DropdownMenuItem(
                  value: 'all', child: Text(l10n.skillsFilterAll)),
              DropdownMenuItem(
                  value: 'installed',
                  child: Text(l10n.skillsFilterInstalled)),
              DropdownMenuItem(
                  value: 'uninstalled',
                  child: Text(l10n.skillsFilterUninstalled)),
            ],
            onChanged: (v) {
              setState(() => _filterStatus = v ?? 'all');
              _pagingController.refresh();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSkillsShInput(
    BuildContext context,
    SkillCubit cubit,
    AppLocalizations l10n,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _skillsShCtl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: l10n.skillsSkillsShPlaceholder,
              isDense: true,
            ),
            onSubmitted: (v) {
              if (v.trim().length >= 2) cubit.searchSkillsSh(v.trim());
            },
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _skillsShCtl.text.trim().length < 2
              ? null
              : () => cubit.searchSkillsSh(_skillsShCtl.text.trim()),
          child: Text(l10n.skillsSkillsShSearch),
        ),
      ],
    );
  }

  Widget _buildReposPagedGrid(
    BuildContext context,
    SkillState state,
    Set<String> installedKeys,
  ) {
    final l10n = context.l10n;
    if (state.discoveryLoading && state.discoverable.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!state.discoveryLoading && state.discoverable.isEmpty) {
      return _Card(
        child: _EmptyBlock(
          icon: Icons.travel_explore_outlined,
          title: l10n.skillsDiscoveryEmpty,
          hint: l10n.skillsDiscoveryEmptyHint,
          actionLabel: state.repos.isEmpty ? l10n.skillsRepoAdd : null,
          onAction: state.repos.isEmpty ? widget.onGoRepos : null,
        ),
      );
    }

    return Expanded(
      child: ValueListenableBuilder<PagingState<int, DiscoverableSkill>>(
        valueListenable: _pagingController,
        builder: (context, pagingState, _) {
          return PagedGridView<int, DiscoverableSkill>(
            state: pagingState,
            fetchNextPage: _pagingController.fetchNextPage,
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 380,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 168,
        ),
        padding: const EdgeInsets.only(top: 2),
        builderDelegate: PagedChildBuilderDelegate<DiscoverableSkill>(
          firstPageProgressIndicatorBuilder: (_) =>
              const SizedBox.shrink(),
          newPageProgressIndicatorBuilder: (_) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          noItemsFoundIndicatorBuilder: (_) => const SizedBox.shrink(),
          itemBuilder: (context, d, index) {
            final installKey =
                '${d.directory.split('/').last.toLowerCase()}:${d.repoOwner.toLowerCase()}:${d.repoName.toLowerCase()}';
            return _SkillCard(
              name: d.name,
              description: d.description,
              source: '${d.repoOwner}/${d.repoName}',
              readmeUrl: d.readmeUrl,
              installed: installedKeys.contains(installKey),
              busy: state.busyIds.contains(d.key),
              onInstall: () =>
                  context.read<SkillCubit>().installFromDiscovery(d),
            );
          },
        ),
          );
        },
      ),
    );
  }

  Widget _buildSkillsShGrid(
    BuildContext context,
    SkillState state,
    SkillCubit cubit,
    Set<String> installedKeys,
  ) {
    final l10n = context.l10n;
    final sh = state.skillsSh;
    if (sh.loading && sh.entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (sh.query.isEmpty) {
      return _Card(
        child: _EmptyBlock(
          icon: Icons.search,
          title: l10n.skillsSkillsShPlaceholder,
          hint: '',
        ),
      );
    }
    if (sh.entries.isEmpty) {
      return _Card(
        child: _EmptyBlock(
          icon: Icons.search_off,
          title: l10n.skillsDiscoveryEmpty,
          hint: l10n.skillsDiscoveryEmptyHint,
        ),
      );
    }

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1100
                ? 3
                : (constraints.maxWidth >= 700 ? 2 : 1);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 168,
              ),
              itemCount: sh.entries.length,
              itemBuilder: (context, i) {
                final e = sh.entries[i];
                final installKey =
                    '${e.directory.toLowerCase()}:${e.repoOwner.toLowerCase()}:${e.repoName.toLowerCase()}';
                return _SkillCard(
                  name: e.name,
                  description: l10n.skillsInstalls(e.installs),
                  source: '${e.repoOwner}/${e.repoName}',
                  readmeUrl: e.readmeUrl,
                  installed: installedKeys.contains(installKey),
                  busy: state.busyIds.contains(e.key),
                  onInstall: () => cubit.installSkillsShEntry(e),
                );
              },
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            children: [
              if (sh.entries.length < sh.totalCount)
                OutlinedButton.icon(
                  onPressed: sh.loading ? null : cubit.loadMoreSkillsSh,
                  icon: sh.loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more, size: 16),
                  label: Text(l10n.skillsSkillsShLoadMore),
                ),
              const SizedBox(height: 6),
              Text(
                l10n.skillsSkillsShPoweredBy,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceToggle extends StatelessWidget {
  const _SourceToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: selected ? colors.selectedBackground : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? colors.selectedBorder : colors.unselectedBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.name,
    required this.description,
    required this.source,
    this.readmeUrl,
    required this.installed,
    required this.busy,
    required this.onInstall,
  });

  final String name;
  final String description;
  final String source;
  final String? readmeUrl;
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: textBase,
                  ),
                ),
              ),
              if (readmeUrl != null)
                InkWell(
                  onTap: () => _openUrl(readmeUrl!),
                  child: Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: textBase.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            source,
            style: TextStyle(
              fontSize: 11,
              color: textBase.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: textBase.withValues(alpha: 0.7),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: installed
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.skillsCardInstalled,
                      style: const TextStyle(
                        color: Color(0xFF15803D),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : FilledButton(
                    onPressed: busy ? null : onInstall,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.skillsCardInstall),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Repos section
// ============================================================================

class _ReposSection extends StatefulWidget {
  const _ReposSection({required this.state});
  final SkillState state;

  @override
  State<_ReposSection> createState() => _ReposSectionState();
}

class _ReposSectionState extends State<_ReposSection> {
  final _ownerCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _branchCtl = TextEditingController(text: 'main');

  @override
  void dispose() {
    _ownerCtl.dispose();
    _nameCtl.dispose();
    _branchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SkillCubit>();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(title: l10n.skillsNavRepos),
                const SizedBox(height: 12),
                if (widget.state.repos.isEmpty)
                  _EmptyBlock(
                    icon: Icons.source_outlined,
                    title: l10n.skillsReposEmpty,
                    hint: l10n.skillsDiscoveryEmptyHint,
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final r in widget.state.repos)
                        _RepoRow(repo: r),
                    ],
                  ),
              ],
            ),
          ),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CardHeader(title: l10n.skillsRepoAdd),
                const SizedBox(height: 12),
                _FieldLabel(text: l10n.skillsRepoOwner),
                const SizedBox(height: 4),
                TextField(controller: _ownerCtl),
                const SizedBox(height: 10),
                _FieldLabel(text: l10n.skillsRepoName),
                const SizedBox(height: 4),
                TextField(controller: _nameCtl),
                const SizedBox(height: 10),
                _FieldLabel(text: l10n.skillsRepoBranch),
                const SizedBox(height: 4),
                TextField(controller: _branchCtl),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final owner = _ownerCtl.text.trim();
                      final name = _nameCtl.text.trim();
                      var branch = _branchCtl.text.trim();
                      if (owner.isEmpty || name.isEmpty) return;
                      if (branch.isEmpty) branch = 'main';
                      await cubit.addRepo(SkillRepo(
                        owner: owner,
                        name: name,
                        branch: branch,
                      ));
                      _ownerCtl.clear();
                      _nameCtl.clear();
                      _branchCtl.text = 'main';
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(l10n.skillsAdd),
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

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo});
  final SkillRepo repo;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final cubit = context.read<SkillCubit>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repo.fullName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textBase,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${repo.branch}',
                    style: TextStyle(
                      fontSize: 11,
                      color: textBase.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: repo.enabled,
              onChanged: (v) => cubit.toggleRepoEnabled(repo, v),
            ),
            IconButton(
              tooltip: l10n.skillsRemove,
              onPressed: () async {
                final ok = await _confirm(
                  context,
                  title: l10n.skillsRepoRemove,
                  message: l10n.skillsRepoRemoveConfirm(repo.fullName),
                  confirmLabel: l10n.skillsRemove,
                  destructive: true,
                );
                if (ok) await cubit.removeRepo(repo.owner, repo.name);
              },
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Backups section
// ============================================================================

class _BackupsSection extends StatelessWidget {
  const _BackupsSection({required this.state});
  final SkillState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (state.backups.isEmpty) {
      return _Card(
        child: _EmptyBlock(
          icon: Icons.history,
          title: l10n.skillsBackupsEmpty,
          hint: '',
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in state.backups) _BackupRow(backup: b),
        ],
      ),
    );
  }
}

class _BackupRow extends StatelessWidget {
  const _BackupRow({required this.backup});
  final SkillBackup backup;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final cubit = context.read<SkillCubit>();
    final created = DateTime.fromMillisecondsSinceEpoch(backup.createdAt);
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                        backup.skill.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textBase,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        backup.skill.directory,
                        style: TextStyle(
                          fontSize: 11,
                          color: textBase.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
                if (backup.skill.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    backup.skill.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: textBase.withValues(alpha: 0.65),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  '${l10n.skillsBackupCreatedAt}: ${created.toLocal()}',
                  style: TextStyle(
                    fontSize: 11,
                    color: textBase.withValues(alpha: 0.5),
                  ),
                ),
                Tooltip(
                  message: backup.backupPath,
                  child: Text(
                    backup.backupPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: textBase.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => cubit.restoreBackup(backup),
            child: Text(l10n.skillsBackupRestore),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final ok = await _confirm(
                context,
                title: l10n.skillsBackupDelete,
                message: l10n.skillsBackupDeleteConfirm(backup.skill.name),
                confirmLabel: l10n.skillsBackupDelete,
                destructive: true,
              );
              if (ok) await cubit.deleteBackup(backup);
            },
            child: Text(l10n.skillsBackupDelete),
          ),
        ],
      ),
    );
  }
}
