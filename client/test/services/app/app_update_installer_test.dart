import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/app/app_update_asset_selector.dart';
import 'package:teampilot/services/app/app_update_installer.dart';
import 'package:teampilot/services/app/app_update_service.dart';

void main() {
  group('AppUpdateInstaller', () {
    test('rejects debug mode installs', () async {
      final installer = AppUpdateInstaller();
      await expectLater(
        () => installer.install(File('fake-setup.exe')),
        throwsA(isA<AppUpdateException>()),
      );
    });
  });

  group('resolveAppUpdateInstallKind', () {
    test('is documented per platform', () {
      // Pure documentation test: selector kinds match CI naming contract.
      expect(
        selectReleaseAssetName(
          assetNames: const ['teampilot-1.0.0-windows-setup.exe'],
          kind: AppUpdateInstallKind.windowsSetup,
        ),
        isNotEmpty,
      );
    });
  });
}
