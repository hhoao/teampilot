import 'dart:io';

import 'package:shared_ui/shared_ui.dart';

import 'adapters/desktop_picker_port.dart';
import 'adapters/local_filesystem_port.dart';
import 'adapters/permission_port.dart';

bool teampilotIsDesktop() =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// TeamPilot wiring for [TpFileSelection]: local FS + desktop picker only.
TpFileSelectionDeps teampilotFileSelectionDeps() {
  return TpFileSelectionDeps(
    filesystem: const LocalFilesystemPort(),
    permission: const TeamPilotPermissionPort(),
    gallery: null,
    desktop: const TeamPilotDesktopPickerPort(),
    preview: null,
    strings: TpFileSelectionStrings.english(),
    isDesktop: teampilotIsDesktop,
  );
}
