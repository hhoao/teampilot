import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/skill.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/github_source_url.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/github_details_button.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'skill_management_cards.dart';

class SkillInstalledSection extends StatelessWidget {
  const SkillInstalledSection({super.key, required this.state, required this.onGoDiscovery});
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
          SkillManagementCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkillCardHeader(
                  title: l10n.skillsInstalledCount(state.installed.length),
                  trailing: CardHeaderActionRow(
                    children: [
                      if (state.updates.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: state.toolbarBusy
                              ? null
                              : throttledOnPressed(
                                  'skill_update_all',
                                  cubit.updateAll,
                                ),
                          icon: const Icon(Icons.upgrade, size: AppIconSizes.md),
                          label: Text(
                            l10n.skillsUpdateAll(state.updates.length),
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: state.toolbarBusy
                            ? null
                            : throttledAsync(
                                'skill_import_disk',
                                () => _onImportFromDisk(context),
                              ),
                        icon: const Icon(Icons.folder_open_outlined, size: AppIconSizes.md),
                        label: Text(l10n.skillsImportFromDisk),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.toolbarBusy
                            ? null
                            : throttledAsync(
                                'skill_install_zip',
                                () => _onInstallZip(context),
                              ),
                        icon: const Icon(Icons.archive_outlined, size: AppIconSizes.md),
                        label: Text(l10n.skillsInstallFromZip),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.toolbarBusy || state.updatesLoading
                            ? null
                            : throttledOnPressed(
                                'skill_check_updates',
                                cubit.checkUpdates,
                              ),
                        icon: state.updatesLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, size: AppIconSizes.md),
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
                  SkillEmptyBlock(
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
                        SkillInstalledRow(
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
      showSkillSnack(context, l10n.skillsImportNothing);
      return;
    }
    final selected = await showDialog<List<UnmanagedSkill>>(
      context: context,
      builder: (_) => SkillImportUnmanagedDialog(skills: scanned),
    );
    if (selected == null || selected.isEmpty) return;
    if (!context.mounted) return;
    await context.read<SkillCubit>().importUnmanaged(selected);
  }
}

class SkillInstalledRow extends StatelessWidget {
  const SkillInstalledRow({super.key, 
    required this.skill,
    this.updateInfo,
    this.busy = false,
  });
  final Skill skill;
  final SkillUpdateInfo? updateInfo;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
        decoration: workspaceInsetDecoration(cs, radius: 10),
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
                          style: AppTextStyles.of(
                            context,
                          ).bodyStrong.copyWith(color: textBase),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: AppTextStyles.of(context).caption.copyWith(
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
                            style: AppTextStyles.of(context).caption.copyWith(
                              color: const Color(0xFFB45309),
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
                      style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: textBase.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            GithubDetailsButton(
              url: skill.githubBrowseUrl,
              label: l10n.skillsCardDetails,
            ),
            const SizedBox(width: 8),
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
                    : const Icon(Icons.upgrade, size: AppIconSizes.md),
              ),
            IconButton(
              tooltip: l10n.skillsCardUninstall,
              onPressed: busy ? null : () => _onUninstall(context, skill),
              icon: Icon(
                Icons.delete_outline,
                size: AppIconSizes.md,
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
    final ok = await skillConfirmDialog(
      context,
      title: l10n.skillsCardUninstall,
      message: l10n.skillsUninstallConfirm(s.name),
      confirmLabel: l10n.skillsCardUninstall,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await context.read<SkillCubit>().uninstall(s);
    if (!context.mounted) return;
    showSkillSnack(context, l10n.skillsUninstallSuccess(s.name));
  }
}

class SkillImportUnmanagedDialog extends StatefulWidget {
  const SkillImportUnmanagedDialog({super.key, required this.skills});
  final List<UnmanagedSkill> skills;

  @override
  State<SkillImportUnmanagedDialog> createState() =>
      SkillImportUnmanagedDialogState();
}

class SkillImportUnmanagedDialogState extends State<SkillImportUnmanagedDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.skills.map((s) => s.directory).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppDialog(
      maxWidth: 560,
      maxHeight: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.skillsImportTitle),
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
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
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
    );
  }
}
