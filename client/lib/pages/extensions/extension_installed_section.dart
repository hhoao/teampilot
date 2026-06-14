import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/extension_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../skills/skill_management_cards.dart';

/// Global Extensions list: install/uninstall + global enable toggle for every
/// known extension manifest. Mirrors the Skills "Installed" section styling.
class ExtensionInstalledSection extends StatelessWidget {
  const ExtensionInstalledSection({super.key, required this.state});

  final ExtensionUiState state;

  String _statusText(BuildContext context, ExtensionRow row) {
    final l10n = context.l10n;
    return switch (row.status) {
      ExtensionStatusCode.notInstalled => l10n.extensionStatusNotInstalled,
      ExtensionStatusCode.dependencyMissing => row.missingRequirements.isEmpty
          ? l10n.extensionStatusDependencyMissing
          : l10n.extensionStatusDependencyMissingNamed(
              row.missingRequirements.join(', '),
            ),
      ExtensionStatusCode.versionTooOld => l10n.extensionStatusVersionTooOld,
      ExtensionStatusCode.ready => () {
          final v = row.version?.trim();
          return (v == null || v.isEmpty)
              ? l10n.extensionStatusReady
              : l10n.extensionStatusReadyVersion(v);
        }(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loading =
        state.status == ExtensionLoadStatus.loading && state.rows.isEmpty;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkillManagementCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkillCardHeader(
                  title: l10n.extensionsSettingsTitle,
                  trailing: _CountBadge(count: state.rows.length),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.extensionsSettingsDescription,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 14),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (state.rows.isEmpty)
                  SkillEmptyBlock(
                    icon: Icons.power_outlined,
                    title: l10n.extensionsEmptyTitle,
                    hint: l10n.extensionsEmptyHint,
                  )
                else
                  for (final row in state.rows)
                    _ExtensionRow(
                      row: row,
                      busy: state.busyIds.contains(row.id),
                      statusText: _statusText(context, row),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count',
        style: AppTextStyles.of(context).caption.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _ExtensionRow extends StatelessWidget {
  const _ExtensionRow({
    required this.row,
    required this.busy,
    required this.statusText,
  });

  final ExtensionRow row;
  final bool busy;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cubit = context.read<ExtensionCubit>();
    final subtitle = row.homepage.isNotEmpty ? row.homepage : row.description;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: styles.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(
                        installed: row.installed,
                        ready: row.status == ExtensionStatusCode.ready,
                        label: statusText,
                      ),
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.bodySmall.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              if (row.installed && row.status != ExtensionStatusCode.ready)
                TextButton(
                  onPressed: () => cubit.recheck(row.id),
                  child: Text(l10n.extensionRecheck),
                ),
              TextButton(
                onPressed: row.installed
                    ? () => cubit.uninstall(row.id)
                    : () => cubit.install(row.id),
                child: Text(
                  row.installed
                      ? l10n.extensionUninstall
                      : l10n.extensionInstall,
                ),
              ),
              Switch(
                value: row.globalEnabled,
                onChanged: row.installed
                    ? (v) => cubit.setGlobalEnabled(row.id, v)
                    : null,
              ),
            ],
          ],
            ),
            if (row.status == ExtensionStatusCode.dependencyMissing &&
                row.missingRequirements.isNotEmpty)
              _DependencyRemediation(row: row),
          ],
        ),
      ),
    );
  }
}

/// Shown under an extension row when its tool is present but a companion
/// dependency (e.g. `jq` for RTK) is missing. Names the dependency, offers a
/// copyable platform-appropriate install command, and points at "Re-check".
class _DependencyRemediation extends StatelessWidget {
  const _DependencyRemediation({required this.row});

  final ExtensionRow row;

  /// Best-effort install command for [dep] on the current desktop host.
  /// Extension acquisition is desktop-local in this phase, so the local OS is
  /// the right target.
  static String _installCommand(String dep) {
    if (Platform.isWindows) return 'winget install $dep';
    if (Platform.isMacOS) return 'brew install $dep';
    return 'sudo apt install $dep';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final deps = row.missingRequirements.join(', ');
    final command = row.missingRequirements.map(_installCommand).join(' && ');

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.error.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.extensionDependencyMissingHint(deps),
              style: styles.bodySmall.copyWith(
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: cs.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Text(
                      command,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.bodySmall.copyWith(
                        fontFamily: 'monospace',
                        color: cs.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: command));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.extensionCommandCopied)),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(l10n.extensionCopyCommand),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.installed,
    required this.ready,
    required this.label,
  });

  final bool installed;
  final bool ready;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color color = !installed
        ? cs.onSurfaceVariant
        : ready
            ? cs.primary
            : cs.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: AppTextStyles.of(context).caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
