import 'package:teampilot_fs/teampilot_fs.dart';

import 'launch_manifest.dart';
import 'session_init_request.dart';
import 'session_init_result.dart';
import 'session_layout.dart';

abstract interface class SessionCliPlugin {
  String get toolId;

  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  });

  String sessionConfigDir(SessionLayout layout, SessionInitRequest request);

  Future<void> afterApply({
    required Filesystem workFs,
    required SessionLayout layout,
    required Map<String, String> environment,
  });

  SessionSpawnSpec buildSpawn({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Map<String, String> environment,
  });
}
