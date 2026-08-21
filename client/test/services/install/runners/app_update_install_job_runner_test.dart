import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:teampilot/models/app_release_info.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_cancelled_exception.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/services/install/install_job_keys.dart';
import 'package:teampilot/services/install/runners/app_update_install_job_runner.dart';

final _release = AppReleaseInfo(
  version: Version(2, 2, 0),
  tagName: 'v2.2.0',
  releaseNotes: 'Notes',
  downloadUrl: 'https://example.com/app.dmg',
  assetName: 'app.dmg',
  fileSize: 1000,
  htmlUrl: 'https://example.com/releases/v2.2.0',
);

void main() {
  group('AppUpdateInstallJobRunner', () {
    test('supports appUpdate keys', () {
      final runner = AppUpdateInstallJobRunner();
      expect(runner.supports(InstallJobKeys.appUpdate('2.2.0')), isTrue);
      expect(runner.supports(InstallJobKeys.skill('lint')), isFalse);
    });

    test('execute reports download progress then installs', () async {
      final phases = <String>[];
      File? installedPackage;

      final runner = AppUpdateInstallJobRunner(
        downloadOverride: (release, {onProgress}) async {
          expect(release.version.toString(), '2.2.0');
          onProgress?.call(0.25);
          onProgress?.call(1.0);
          return File('/tmp/app.dmg');
        },
        installOverride: (package) async {
          installedPackage = package;
        },
      );

      await runner.execute(
        key: InstallJobKeys.appUpdate('2.2.0'),
        release: _release,
        ctx: InstallJobContext(
          reportPhase: (label, {detail, fraction}) {
            phases.add(
              fraction == null ? label : '$label@${fraction.toStringAsFixed(2)}',
            );
          },
        ),
        downloadingSubtitle: 'Downloading update…',
        installingSubtitle: 'Installing update…',
      );

      expect(phases, [
        'Downloading update…@0.00',
        'Downloading update…@0.25',
        'Downloading update…@1.00',
        'Installing update…',
      ]);
      expect(installedPackage?.path, '/tmp/app.dmg');
    });

    test('execute throws when download is cancelled', () async {
      final runner = AppUpdateInstallJobRunner(
        downloadOverride: (release, {onProgress}) async {
          onProgress?.call(0.1);
          return File('/tmp/app.dmg');
        },
        installOverride: (_) async {},
      );
      final ctx = InstallJobContext()..requestCancel();
      final key = InstallJobKeys.appUpdate('2.2.0');

      await expectLater(
        runner.execute(
          key: key,
          release: _release,
          ctx: ctx,
          downloadingSubtitle: 'Downloading update…',
          installingSubtitle: 'Installing update…',
        ),
        throwsA(isA<InstallJobCancelledException>()),
      );
    });

    test('execute does not check cancellation during install phase', () async {
      var installStarted = false;
      final runner = AppUpdateInstallJobRunner(
        downloadOverride: (release, {onProgress}) async => File('/tmp/app.dmg'),
        installOverride: (package) async {
          installStarted = true;
        },
      );
      final ctx = InstallJobContext();
      ctx.requestCancel();

      await runner.execute(
        key: InstallJobKeys.appUpdate('2.2.0'),
        release: _release,
        ctx: ctx,
        downloadingSubtitle: 'Downloading update…',
        installingSubtitle: 'Installing update…',
      );

      expect(installStarted, isTrue);
    });

    test('run delegates to spec.run', () async {
      final runner = AppUpdateInstallJobRunner();
      final key = InstallJobKeys.appUpdate('2.2.0');
      final spec = InstallJobSpec<String>(
        key: key,
        title: 'Update',
        cancelPolicy: InstallCancelPolicy.forceKill,
        run: (ctx) async => 'done',
      );

      expect(await runner.run(spec, InstallJobContext()), 'done');
    });
  });
}
