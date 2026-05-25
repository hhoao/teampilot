import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:android_package_installer/android_package_installer.dart';
import 'app_update_asset_selector.dart';
import 'app_update_service.dart';

/// Installs a downloaded release package for the current platform.
class AppUpdateInstaller {
  AppUpdateInstaller({
    AppUpdateInstallKind Function()? installKindResolver,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    processRunner,
    void Function(int code)? exitProcess,
  }) : _installKindResolver =
           installKindResolver ?? resolveAppUpdateInstallKind,
       _processRunner =
           processRunner ??
           ((executable, arguments) =>
               Process.run(executable, arguments, runInShell: true)),
       _exitProcess = exitProcess ?? ((_) => exit(0));

  final AppUpdateInstallKind Function() _installKindResolver;
  final Future<ProcessResult> Function(
    String executable,
    List<String> arguments,
  )
  _processRunner;
  final void Function(int code) _exitProcess;

  /// Throws [AppUpdateException] when install cannot proceed.
  Future<void> install(File packageFile) async {
    if (kDebugMode) {
      throw AppUpdateException(
        'Install updates from a release build, not debug mode.',
      );
    }
    if (!await packageFile.exists()) {
      throw AppUpdateException('Update file not found: ${packageFile.path}');
    }

    final kind = _installKindResolver();
    switch (kind) {
      case AppUpdateInstallKind.windowsSetup:
        await _installWindowsSetup(packageFile);
      case AppUpdateInstallKind.linuxAppImage:
        await _installLinuxAppImage(packageFile);
      case AppUpdateInstallKind.linuxDeb:
        await _installLinuxDeb(packageFile);
      case AppUpdateInstallKind.macosDmg:
        await _installMacosDmg(packageFile);
      case AppUpdateInstallKind.androidApk:
        await _installAndroidApk(packageFile);
    }
  }

  Future<void> _installWindowsSetup(File exe) async {
    final process = await Process.start(
      exe.path,
      const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
      mode: ProcessStartMode.detached,
    );
    await process.exitCode;
    _exitProcess(0);
  }

  Future<void> _installLinuxAppImage(File downloaded) async {
    final current = Platform.environment['APPIMAGE'];
    if (current == null || current.isEmpty) {
      throw AppUpdateException(
        'APPIMAGE is not set. Use the AppImage build to receive in-app updates.',
      );
    }

    await Process.run('chmod', ['+x', downloaded.path]);
    final targetDir = p.dirname(current);
    final target = File(p.join(targetDir, p.basename(downloaded.path)));
    if (target.path != downloaded.path) {
      if (await target.exists()) {
        await target.delete();
      }
      await downloaded.copy(target.path);
      await Process.run('chmod', ['+x', target.path]);
    }

    await Process.start(
      target.path,
      [],
      mode: ProcessStartMode.detached,
      workingDirectory: targetDir,
    );
    _exitProcess(0);
  }

  Future<void> _installLinuxDeb(File deb) async {
    final result = await _processRunner('pkexec', [
      'dpkg',
      '-i',
      deb.path,
    ]);
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String?)?.trim() ?? '';
      throw AppUpdateException(
        stderr.isEmpty
            ? 'Installing .deb failed (exit ${result.exitCode}). '
                  'Run manually: sudo dpkg -i ${deb.path}'
            : stderr,
      );
    }
    _exitProcess(0);
  }

  Future<void> _installMacosDmg(File dmg) async {
    final attach = await _processRunner('hdiutil', [
      'attach',
      '-nobrowse',
      '-quiet',
      dmg.path,
    ]);
    if (attach.exitCode != 0) {
      throw AppUpdateException(
        'Could not mount DMG: ${attach.stderr}',
      );
    }

    String? mountPoint;
    final lines = (attach.stdout as String).split('\n');
    for (final line in lines) {
      final parts = line.split('\t');
      if (parts.length >= 3 && parts.last.contains('/Volumes/')) {
        mountPoint = parts.last.trim();
        break;
      }
    }
    mountPoint ??= '/Volumes/TeamPilot';

    try {
      final bundleName = await _findAppBundleInMount(mountPoint);
      final source = p.join(mountPoint, bundleName);
      const destDir = '/Applications';
      final dest = p.join(destDir, bundleName);

      final copy = await _processRunner('cp', ['-R', source, dest]);
      if (copy.exitCode != 0) {
        throw AppUpdateException(
          'Could not copy to Applications: ${copy.stderr}',
        );
      }

      await _processRunner('open', ['-a', dest]);
    } finally {
      await _processRunner('hdiutil', ['detach', mountPoint, '-quiet']);
    }
    _exitProcess(0);
  }

  Future<String> _findAppBundleInMount(String mountPoint) async {
    final dir = Directory(mountPoint);
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.app')) {
        return p.basename(entity.path);
      }
      if (entity is Directory && entity.path.endsWith('.app')) {
        return p.basename(entity.path);
      }
    }
    throw AppUpdateException('No .app bundle found in DMG at $mountPoint');
  }

  Future<void> _installAndroidApk(File apk) async {
    final statusCode = await AndroidPackageInstaller.installApk(
      apkFilePath: apk.path,
    );
    if (statusCode == null) {
      throw AppUpdateException('APK install returned no status');
    }
    final status = PackageInstallerStatus.byCode(statusCode);
    if (status != PackageInstallerStatus.success) {
      throw AppUpdateException('APK install failed: ${status.name}');
    }
  }
}
