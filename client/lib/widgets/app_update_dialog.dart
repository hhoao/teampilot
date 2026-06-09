import 'dart:io';

import 'package:android_package_installer/android_package_installer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/models/app_models.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/app/app_update_installer.dart';
import 'package:teampilot/services/app/app_update_service.dart';
import 'package:teampilot/services/app/backend_app_update_service.dart';
import 'package:teampilot/theme/app_text_styles.dart';
import 'package:teampilot/utils/changelog_parser.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:url_launcher/url_launcher.dart';

/// Backend-driven update dialog: download and install on Android and desktop.
class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
    this.downloadService,
    this.packageInstaller,
  });

  final AppUpdateInfo updateInfo;
  final BackendAppUpdateService? downloadService;
  final AppUpdateInstaller? packageInstaller;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  late final BackendAppUpdateService _downloadService =
      widget.downloadService ?? BackendAppUpdateService();

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  late String _downloadStatus;
  bool _isExpanded = false;
  List<ChangelogEntry> _changelogs = const [];
  bool _downloadCompleted = false;
  String _downloadSavePath = '';
  bool _installInProgress = false;
  bool _localized = false;

  @override
  void dispose() {
    _downloadService.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_localized) return;
    _localized = true;
    final l10n = context.l10n;
    _downloadStatus = l10n.appUpdateReadyToDownload;
    _changelogs = ChangelogData.parseMarkdownContent(
      widget.updateInfo.changelogs?.join('\n') ?? '',
      defaultSectionTitle: l10n.appUpdateChangelogDefaultSection,
    );
  }

  DownloadTypeEnum? get _downloadType =>
      widget.updateInfo.downloadType ??
      widget.updateInfo.latestApp?.downloadType;

  bool get _isRedirectDownload => _downloadType == DownloadTypeEnum.redirect;

  bool get _supportsInAppInstall =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux);

  AppUpdateInstaller get _packageInstaller =>
      widget.packageInstaller ?? AppUpdateInstaller();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final latestApp = widget.updateInfo.latestApp;
    final currentApp = widget.updateInfo.currentApp;

    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            Center(
              child: Text(
                l10n.appUpdateDialogTitle,
                style: AppTextStyles.of(context).dialogTitle.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildVersionInfo(l10n, latestApp, currentApp),
                    ),
                    if (_isDownloading || _downloadCompleted)
                      _buildDownloadProgress(),
                    if (latestApp != null) _buildBottomRow(l10n, latestApp),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionInfo(
    AppLocalizations l10n,
    AppApplicationRespVO? latestApp,
    AppApplicationRespVO? currentApp,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.aboutCurrentVersion,
                      style: AppTextStyles.of(context).body.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentApp?.version ?? '—',
                      style: AppTextStyles.of(context).body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: Colors.grey[400]),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      l10n.appUpdateLatestVersion,
                      style: AppTextStyles.of(context).body.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latestApp?.version ?? l10n.appUpdateUnknownVersion,
                      style: AppTextStyles.of(context).body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_changelogs.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                shape: Border.all(color: Colors.transparent),
                collapsedShape: Border.all(color: Colors.transparent),
                backgroundColor: Colors.transparent,
                collapsedBackgroundColor: Colors.transparent,
                title: Text(
                  l10n.appUpdateChangelogTitle,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                collapsedIconColor: Colors.grey[600],
                collapsedTextColor: Colors.grey[600],
                textColor: Colors.grey[600],
                iconColor: Colors.grey[600],
                trailing: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey[600],
                  size: AppIconSizes.md,
                ),
                onExpansionChanged: (expanded) {
                  setState(() => _isExpanded = expanded);
                },
                children: [
                  SizedBox(
                    height: 200,
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final changelog in _changelogs) ...[
                              ChangelogData.buildChangelogItem(
                                context,
                                changelog,
                              ),
                              const SizedBox(height: 12),
                            ],
                          ],
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

  Widget _buildDownloadProgress() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _downloadStatus,
                  style: AppTextStyles.of(context).bodySmall.copyWith(
                    color: Colors.blue[700],
                  ),
                ),
              ),
              Text(
                '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                style: AppTextStyles.of(context).bodyStrong.copyWith(
                  color: Colors.blue[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _downloadCompleted ? 1 : _downloadProgress,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            minHeight: 8,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildBottomRow(
    AppLocalizations l10n,
    AppApplicationRespVO latestApp,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Flex(
        direction: Axis.horizontal,
        children: [
          if (!widget.updateInfo.forceUpdate)
            Expanded(
              child: _buildBottomButton(
                _isDownloading ? null : () => Navigator.of(context).pop(),
                null,
                l10n.appUpdateLater,
              ),
            ),
          if (!_isRedirectDownload)
            Expanded(
              child: _buildBottomButton(
                _installInProgress ? null : _onPrimaryAction,
                null,
                _primaryButtonLabel(l10n),
              ),
            ),
          if (_isRedirectDownload && !_isDownloading && !_downloadCompleted)
            Expanded(
              child: _buildBottomButton(
                () => _handleBrowserDownload(latestApp),
                const Icon(Icons.open_in_browser, size: AppIconSizes.md),
                l10n.appUpdateBrowserDownload,
              ),
            ),
        ],
      ),
    );
  }

  String _primaryButtonLabel(AppLocalizations l10n) {
    if (_installInProgress) return l10n.appUpdateInstalling;
    if (_downloadCompleted) return l10n.appUpdateInstallNow;
    if (_isDownloading) return l10n.appUpdateDownloadInBackground;
    return l10n.appUpdateDownloadNow;
  }

  void _onPrimaryAction() {
    if (_downloadCompleted) {
      _handleInstall();
      return;
    }
    if (_isDownloading) {
      Navigator.of(context).pop();
      return;
    }
    final latest = widget.updateInfo.latestApp;
    if (latest != null) {
      _handleDownload(latest);
    }
  }

  Future<void> _handleInstall() async {
    final l10n = context.l10n;
    if (!_downloadCompleted || !_supportsInAppInstall) return;
    if (_downloadSavePath.isEmpty) {
      _showSnackBar(l10n.appUpdateInvalidPackagePath, isError: true);
      return;
    }

    if (kDebugMode) {
      _showSnackBar(l10n.appUpdateReleaseBuildRequired, isError: true);
      return;
    }

    if (!BackendAppUpdateService.packageMatchesCurrentPlatform(
      _downloadSavePath,
    )) {
      _showSnackBar(l10n.appUpdatePackagePlatformMismatch, isError: true);
      return;
    }

    setState(() => _installInProgress = true);
    try {
      if (Platform.isAndroid) {
        await _installAndroidApk(_downloadSavePath);
      } else {
        await _packageInstaller.install(File(_downloadSavePath));
      }
    } on AppUpdateException catch (e) {
      if (mounted) {
        _showSnackBar(l10n.appUpdateInstallFailed(e.message), isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(l10n.appUpdateInstallFailed('$e'), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _installInProgress = false);
      }
    }
  }

  Future<void> _installAndroidApk(String path) async {
    final l10n = context.l10n;
    final statusCode = await AndroidPackageInstaller.installApk(
      apkFilePath: path,
    );
    if (!mounted) return;

    if (statusCode == null) {
      _showSnackBar(l10n.appUpdateInstallNoResult, isError: true);
      return;
    }

    final status = PackageInstallerStatus.byCode(statusCode);
    if (status == PackageInstallerStatus.success) {
      _showSnackBar(l10n.appUpdateInstallComplete);
      Navigator.of(context).pop();
    } else {
      _showSnackBar(l10n.appUpdateInstallFailed(status.name), isError: true);
    }
  }

  Future<void> _handleDownload(AppApplicationRespVO latestApp) async {
    final l10n = context.l10n;
    if (_downloadType == DownloadTypeEnum.redirect) {
      _showSnackBar(l10n.appUpdateRedirectBrowserOnly);
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatus = l10n.appUpdateDownloadStarting;
      _downloadCompleted = false;
      _downloadSavePath = '';
    });

    try {
      final url = _downloadService.resolveDownloadUrl(
        widget.updateInfo,
        latestApp,
      );
      final resolvedName = BackendAppUpdateService.suggestedPackageFileName(
        app: latestApp,
        downloadUrl: url,
      );

      final file = await _downloadService.downloadPackage(
        url: url,
        fileName: resolvedName,
        onProgress: (progress, label) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = progress.clamp(0.0, 1.0);
            _downloadStatus = label;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _downloadCompleted = true;
        _downloadSavePath = file.path;
        _downloadProgress = 1;
        _downloadStatus = l10n.appUpdateDownloadComplete;
        _isDownloading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadStatus = l10n.appUpdateDownloadFailed;
      });
      _showSnackBar(l10n.appUpdateDownloadError('$e'), isError: true);
    }
  }

  Future<void> _handleBrowserDownload(AppApplicationRespVO latestApp) async {
    final l10n = context.l10n;
    _showSnackBar(l10n.appUpdateResolvingDownloadUrl, long: true);

    try {
      final downloadUrl = _downloadService.resolveDownloadUrl(
        widget.updateInfo,
        latestApp,
      );

      final finalUrl = await _downloadService.resolveFinalDownloadUrl(
        downloadUrl,
      );
      final uri = Uri.parse(finalUrl);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (launched) {
        _showSnackBar(l10n.appUpdateBrowserOpened);
      } else {
        _showSnackBar(l10n.appUpdateCannotOpenDownloadLink, isError: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showSnackBar(l10n.appUpdateBrowserOpenFailed('$e'), isError: true);
      }
    }
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    bool long = false,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: long
            ? const Duration(seconds: 30)
            : const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildBottomButton(
    VoidCallback? onPressed,
    Widget? prefix,
    String text,
  ) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.blue[400],
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (prefix != null) prefix,
          Text(text, style: AppTextStyles.of(context).body),
        ],
      ),
    );
  }
}

/// Shows [AppUpdateDialog] using the root [GoRouter] navigator.
class AppUpdateDialogHelper {
  static void show({required AppUpdateInfo updateInfo}) {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final delayedContext =
            appRouter.routerDelegate.navigatorKey.currentContext;
        if (delayedContext != null && delayedContext.mounted) {
          showDialog(
            context: delayedContext,
            barrierDismissible: !updateInfo.forceUpdate,
            builder: (context) => AppUpdateDialog(updateInfo: updateInfo),
          );
        }
      });
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (context) => AppUpdateDialog(updateInfo: updateInfo),
    );
  }
}

/// Resolves the running app version label for the update dialog.
Future<String> resolveCurrentAppVersionLabel() async {
  final info = await PackageInfo.fromPlatform();
  final build = info.buildNumber.trim();
  if (build.isEmpty || build == '0') return info.version;
  return '${info.version}+$build';
}
