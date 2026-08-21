import 'dart:io';

import 'package:meta/meta.dart';

import '../../../models/app_release_info.dart';
import '../../../models/install_job/install_job_cancelled_exception.dart';
import '../../../models/install_job/install_job_context.dart';
import '../../../models/install_job/install_job_key.dart';
import '../../../models/install_job/install_job_spec.dart';
import '../../app/app_update_installer.dart';
import '../../app/app_update_service.dart';
import '../install_job_runner.dart';

typedef AppUpdateDownloadInvoke =
    Future<File> Function(
      AppReleaseInfo release, {
      void Function(double progress)? onProgress,
    });

typedef AppUpdateInstallInvoke = Future<void> Function(File package);

final class AppUpdateInstallJobRunner implements InstallJobRunner {
  AppUpdateInstallJobRunner({
    AppUpdateService? service,
    AppUpdateInstaller? installer,
    AppReleaseInfo Function(String version)? releaseForVersion,
    @visibleForTesting AppUpdateDownloadInvoke? downloadOverride,
    @visibleForTesting AppUpdateInstallInvoke? installOverride,
  }) : _service = service ?? AppUpdateService(),
       _installer = installer ?? AppUpdateInstaller(),
       _releaseForVersion = releaseForVersion,
       _downloadOverride = downloadOverride,
       _installOverride = installOverride;

  final AppUpdateService _service;
  final AppUpdateInstaller _installer;
  final AppReleaseInfo Function(String version)? _releaseForVersion;
  final AppUpdateDownloadInvoke? _downloadOverride;
  final AppUpdateInstallInvoke? _installOverride;

  @override
  InstallJobKind get kind => InstallJobKind.appUpdate;

  @override
  bool supports(InstallJobKey key) => key.kind == kind;

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    if (!supports(spec.key)) {
      throw StateError('Unsupported app update key: ${spec.key.target}');
    }
    return spec.run(ctx);
  }

  Future<void> execute({
    required InstallJobKey key,
    required AppReleaseInfo release,
    required InstallJobContext ctx,
    required String downloadingSubtitle,
    required String installingSubtitle,
  }) async {
    ctx.reportPhase(downloadingSubtitle, fraction: 0);

    final package = await _download(
      key: key,
      release: release,
      ctx: ctx,
      downloadingSubtitle: downloadingSubtitle,
    );

    ctx.reportPhase(installingSubtitle);
    await _install(package);
  }

  Future<File> _download({
    required InstallJobKey key,
    required AppReleaseInfo release,
    required InstallJobContext ctx,
    required String downloadingSubtitle,
  }) async {
    final override = _downloadOverride;
    if (override != null) {
      return override(
        release,
        onProgress: (progress) => _reportDownloadProgress(
          key: key,
          ctx: ctx,
          downloadingSubtitle: downloadingSubtitle,
          progress: progress,
        ),
      );
    }

    return _service.downloadRelease(
      release,
      onProgress: (progress) => _reportDownloadProgress(
        key: key,
        ctx: ctx,
        downloadingSubtitle: downloadingSubtitle,
        progress: progress,
      ),
    );
  }

  void _reportDownloadProgress({
    required InstallJobKey key,
    required InstallJobContext ctx,
    required String downloadingSubtitle,
    required double progress,
  }) {
    if (ctx.isCancelled) {
      throw InstallJobCancelledException(key);
    }
    ctx.reportPhase(
      downloadingSubtitle,
      fraction: progress.clamp(0.0, 1.0),
    );
  }

  Future<void> _install(File package) {
    final override = _installOverride;
    if (override != null) {
      return override(package);
    }
    return _installer.install(package);
  }

  AppReleaseInfo? releaseForTarget(String target) =>
      _releaseForVersion?.call(target);
}
