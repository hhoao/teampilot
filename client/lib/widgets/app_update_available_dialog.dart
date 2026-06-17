import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cubits/app_update_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_release_info.dart';
import '../router/app_router.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_text_styles.dart';
import '../utils/changelog_parser.dart';
import 'app_dialog.dart';

/// Popup shown when [AppUpdateCubit] surfaces a newer release (e.g. on the
/// startup auto-check). Drives download/install through the shared cubit so the
/// dialog can be dismissed while the download continues in the background.
class AppUpdateAvailableDialog extends StatefulWidget {
  const AppUpdateAvailableDialog({super.key, required this.release});

  final AppReleaseInfo release;

  @override
  State<AppUpdateAvailableDialog> createState() =>
      _AppUpdateAvailableDialogState();
}

class _AppUpdateAvailableDialogState extends State<AppUpdateAvailableDialog> {
  bool _changelogExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final changelogs = ChangelogData.parseMarkdownContent(
      widget.release.releaseNotes,
      defaultSectionTitle: l10n.appUpdateChangelogDefaultSection,
    );

    return BlocBuilder<AppUpdateCubit, AppUpdateState>(
      builder: (context, state) {
        final busy =
            state.status == AppUpdateStatus.downloading ||
            state.status == AppUpdateStatus.installing;

        return AppDialog(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(title: l10n.appUpdateDialogTitle),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      _versionRow(context, state, styles, cs),
                      if (changelogs.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _changelog(context, changelogs, styles, cs),
                      ],
                      if (busy) ...[
                        const SizedBox(height: 16),
                        _progress(context, state, styles, cs),
                      ],
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          state.errorMessage!,
                          style: styles.bodySmall.copyWith(color: cs.error),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _actions(context, state, busy),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _versionRow(
    BuildContext context,
    AppUpdateState state,
    AppTextStyles styles,
    ColorScheme cs,
  ) {
    return Row(
      children: [
        Expanded(
          child: _versionColumn(
            context.l10n.aboutCurrentVersion,
            state.currentVersionLabel.isEmpty
                ? '—'
                : state.currentVersionLabel,
            CrossAxisAlignment.start,
            styles,
            cs,
            highlight: false,
          ),
        ),
        Icon(Icons.arrow_forward, color: cs.onSurfaceVariant),
        Expanded(
          child: _versionColumn(
            context.l10n.appUpdateLatestVersion,
            widget.release.version.toString(),
            CrossAxisAlignment.end,
            styles,
            cs,
            highlight: true,
          ),
        ),
      ],
    );
  }

  Widget _versionColumn(
    String label,
    String value,
    CrossAxisAlignment align,
    AppTextStyles styles,
    ColorScheme cs, {
    required bool highlight,
  }) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: styles.body.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(
          value,
          style: styles.body.copyWith(
            fontWeight: FontWeight.w600,
            color: highlight ? cs.primary : cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _changelog(
    BuildContext context,
    List<ChangelogEntry> changelogs,
    AppTextStyles styles,
    ColorScheme cs,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          context.l10n.appUpdateChangelogTitle,
          style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        collapsedIconColor: cs.onSurfaceVariant,
        iconColor: cs.onSurfaceVariant,
        trailing: Icon(
          _changelogExpanded ? Icons.expand_less : Icons.expand_more,
          color: cs.onSurfaceVariant,
          size: context.appIconSizes.md,
        ),
        onExpansionChanged: (v) => setState(() => _changelogExpanded = v),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in changelogs) ...[
                      ChangelogData.buildChangelogItem(context, entry),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progress(
    BuildContext context,
    AppUpdateState state,
    AppTextStyles styles,
    ColorScheme cs,
  ) {
    final installing = state.status == AppUpdateStatus.installing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              installing
                  ? context.l10n.appUpdateInstalling
                  : context.l10n.appUpdateDownloading,
              style: styles.bodySmall.copyWith(color: cs.primary),
            ),
            if (!installing)
              Text(
                '${(state.downloadProgress * 100).toStringAsFixed(0)}%',
                style: styles.bodyStrong.copyWith(color: cs.primary),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: installing ? null : state.downloadProgress,
          minHeight: 6,
        ),
      ],
    );
  }

  Widget _actions(BuildContext context, AppUpdateState state, bool busy) {
    final l10n = context.l10n;
    final cubit = context.read<AppUpdateCubit>();

    if (busy) {
      // Download continues on the shared cubit; let the user step away.
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.appUpdateDownloadInBackground),
        ),
      );
    }

    final hasError = state.errorMessage != null;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.release.htmlUrl.isNotEmpty)
          TextButton(
            onPressed: () => _open(widget.release.htmlUrl),
            child: Text(l10n.appUpdateViewRelease),
          ),
        if (!hasError)
          TextButton(
            onPressed: () {
              cubit.skipPromptedVersion();
              Navigator.of(context).pop();
            },
            child: Text(l10n.appUpdateSkipVersion),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.appUpdateLater),
        ),
        FilledButton.icon(
          onPressed: () => cubit.downloadAndInstall(),
          icon: const Icon(Icons.download_outlined),
          label: Text(l10n.appUpdateDownloadInstall),
        ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Shows [AppUpdateAvailableDialog] on the root navigator. The [AppUpdateCubit]
/// must already be provided above the router (it is, in `app_shell`).
class AppUpdateAvailableDialogHelper {
  static bool _isOpen = false;

  static Future<void> show(AppReleaseInfo release) async {
    if (_isOpen) return;
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _isOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => BlocProvider.value(
          value: context.read<AppUpdateCubit>(),
          child: AppUpdateAvailableDialog(release: release),
        ),
      );
    } finally {
      _isOpen = false;
    }
  }
}
