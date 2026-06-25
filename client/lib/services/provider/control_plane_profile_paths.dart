import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../storage/runtime_context.dart';
import '../storage/runtime_layout.dart';
import '../cli/registry/config_profile/config_profile_context.dart';

/// Control-plane [ConfigProfilePaths] for reading provider catalog, credentials,
/// and other home-resident configuration. Work-plane writes use
/// [ConfigProfileDelegate] on the member's machine.
final class ControlPlaneProfilePaths implements ConfigProfilePaths {
  ControlPlaneProfilePaths(RuntimeContext context)
    : basePath = context.appDataRoot,
      home = context.home,
      fs = context.filesystem,
      layout = context.layout;

  @override
  final String basePath;
  @override
  final String home;
  @override
  final Filesystem fs;
  @override
  late final p.Context pathContext = fs.pathContext;
  @override
  final RuntimeLayout layout;

  @override
  String sessionToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  }) =>
      layout.sessionRuntimeToolDir(
        workspaceId,
        sessionId,
        tool,
        memberId: memberId,
      );
}
