import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_update_config.dart';
import '../cubits/app_update_cubit.dart';
import '../cubits/config_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../pages/onboarding/onboarding_gate.dart';
import '../utils/app_keys.dart';
import '../widgets/settings/workspace_hub_shell.dart';
import '../widgets/settings/workspace_settings_widgets.dart';

/// About / app update section inside [ConfigWorkspace] (desktop split or Android hub).
class AboutConfigWorkspace extends StatefulWidget {
  const AboutConfigWorkspace({
    this.showHeading = true,
    this.onViewLogs,
    super.key,
  });

  final bool showHeading;

  /// Overrides the default `/config/logs` route navigation for the logs button.
  /// Lets embedders (e.g. the settings dialog) decide how to open the viewer.
  final VoidCallback? onViewLogs;

  @override
  State<AboutConfigWorkspace> createState() => _AboutConfigWorkspaceState();
}

class _AboutConfigWorkspaceState extends State<AboutConfigWorkspace> {
  @override
  void initState() {
    super.initState();
    context.read<AppUpdateCubit>().loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          WorkspaceSectionHeading(
            title: l10n.aboutTitle,
            subtitle: l10n.aboutPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: BlocConsumer<AppUpdateCubit, AppUpdateState>(
            listener: (context, state) {
              if (state.status == AppUpdateStatus.upToDate) {
                AppToast.show(
                  context,
                  message: l10n.appUpdateUpToDate,
                  variant: AppToastVariant.success,
                );
              }
            },
            builder: (context, state) {
              return SingleChildScrollView(
                child: SettingsSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsLabeledRow(
                        title: l10n.aboutCurrentVersion,
                        subtitle: state.currentVersionLabel.isEmpty
                            ? l10n.aboutVersionLoading
                            : state.currentVersionLabel,
                        trailing: _VersionUpdateActions(state: state),
                        showDividerBelow: true,
                      ),
                      SettingsLabeledRow(
                        title: l10n.appUpdateAutoCheck,
                        subtitle: l10n.appUpdateAutoCheckHint,
                        trailing: Switch(
                          key: AppKeys.aboutAutoCheckUpdatesSwitch,
                          value: state.autoCheckEnabled,
                          onChanged: (value) => context
                              .read<AppUpdateCubit>()
                              .setAutoCheckEnabled(value),
                        ),
                        showDividerBelow: true,
                      ),
                      if (state.availableRelease != null) ...[
                        SettingsLabeledStackedRow(
                          title: l10n.appUpdateNewVersion(
                            state.availableRelease!.version.toString(),
                          ),
                          subtitle: state.availableRelease!.assetName,
                          body: _ReleaseNotesPreview(
                            notes: state.availableRelease!.releaseNotes,
                          ),
                          showDividerBelow: true,
                        ),
                      ],
                      if (state.status == AppUpdateStatus.downloading ||
                          state.status == AppUpdateStatus.installing) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LinearProgressIndicator(
                                value:
                                    state.status == AppUpdateStatus.installing
                                    ? null
                                    : state.downloadProgress,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                state.status == AppUpdateStatus.installing
                                    ? l10n.appUpdateInstalling
                                    : l10n.appUpdateDownloading,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (state.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Text(
                            state.errorMessage!,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: cs.error),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (state.status == AppUpdateStatus.available ||
                                state.availableRelease != null)
                              FilledButton.tonalIcon(
                                key: AppKeys.aboutDownloadInstallButton,
                                onPressed: state.isBusy
                                    ? null
                                    : () => context
                                          .read<AppUpdateCubit>()
                                          .downloadAndInstall(),
                                icon: Icon(Icons.download_outlined),
                                label: Text(l10n.appUpdateDownloadInstall),
                              ),
                            if (state.availableRelease?.htmlUrl.isNotEmpty ==
                                true)
                              TextButton(
                                onPressed: () => _openReleasePage(
                                  state.availableRelease!.htmlUrl,
                                ),
                                child: Text(l10n.appUpdateViewRelease),
                              ),
                            TextButton(
                              onPressed: () => resetOnboardingWizard(context),
                              child: Text(l10n.onboardingRerunSetup),
                            ),
                            OutlinedButton.icon(
                              key: AppKeys.configLogsSectionButton,
                              onPressed: () {
                                final onViewLogs = widget.onViewLogs;
                                if (onViewLogs != null) {
                                  onViewLogs();
                                  return;
                                }
                                context.read<ConfigCubit>().selectSection(
                                  ConfigSection.logs,
                                );
                                context.go('/config/logs');
                              },
                              icon: Icon(Icons.article_outlined),
                              label: Text(l10n.logViewerTitle),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openReleasePage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _VersionUpdateActions extends StatelessWidget {
  const _VersionUpdateActions({required this.state});

  final AppUpdateState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final checking = state.status == AppUpdateStatus.checking;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          key: AppKeys.aboutGitHubButton,
          onPressed: () => _openUrl(appUpdateGitHubRepoPageUrl()),
          child: Text(l10n.aboutGitHub),
        ),
        TextButton(
          key: AppKeys.aboutViewReleasesButton,
          onPressed: () => _openUrl(appUpdateGitHubReleasesPageUrl()),
          child: Text(l10n.appUpdateViewReleases),
        ),
        FilledButton(
          key: AppKeys.aboutCheckUpdatesButton,
          onPressed: state.isBusy
              ? null
              : () => context.read<AppUpdateCubit>().checkForUpdates(),
          child: checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.appUpdateCheck),
        ),
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ReleaseNotesPreview extends StatelessWidget {
  const _ReleaseNotesPreview({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final text = notes.trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final preview = text.length > 600 ? '${text.substring(0, 600)}…' : text;
    return SelectableText(
      preview,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
