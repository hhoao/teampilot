import 'package:teampilot_fs/teampilot_fs.dart';

import 'launch_manifest.dart';
import 'session_init_request.dart';
import 'session_layout.dart';

abstract interface class ResourceContributor {
  String get id;
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required LaunchManifest manifest,
  });
}
