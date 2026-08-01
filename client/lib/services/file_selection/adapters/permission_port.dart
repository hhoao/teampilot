import 'dart:io';

import 'package:permission_handler/permission_handler.dart' as permission_handler;
import 'package:shared_ui/shared_ui.dart';

/// Storage permission gate for mobile file browsing; desktop is unrestricted.
class TeamPilotPermissionPort implements TpPermissionPort {
  const TeamPilotPermissionPort();

  static bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  Future<bool> ensureStorageAccess() async {
    if (_isDesktop || !Platform.isAndroid) {
      return true;
    }

    if (await permission_handler.Permission.storage.isGranted) {
      return true;
    }

    final storage = await permission_handler.Permission.storage.request();
    if (storage.isGranted) {
      return true;
    }

    if (await permission_handler.Permission.manageExternalStorage.isGranted) {
      return true;
    }

    final manage =
        await permission_handler.Permission.manageExternalStorage.request();
    return manage.isGranted;
  }

  @override
  Future<bool> ensureGalleryAccess() async => false;

  @override
  Future<void> openAppSettings() async {
    if (_isDesktop) return;
    await permission_handler.openAppSettings();
  }
}
