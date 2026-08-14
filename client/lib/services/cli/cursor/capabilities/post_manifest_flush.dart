import '../../../../utils/logging/logger.dart';
import '../provider/cursor_member_home_passthrough.dart';
import '../../registry/capabilities/post_manifest_flush_capability.dart';

/// Cursor fake-HOME passthrough after session trees exist on disk.
///
/// SSH/Termux: one remote `find`+`ln` script via [PostManifestFlushContext.remoteRunner].
/// Local/WSL: [CursorMemberHomePassthrough.mirror] over the work filesystem.
final class CursorPostManifestFlushCapability
    implements PostManifestFlushCapability {
  const CursorPostManifestFlushCapability();

  static const progressDetail = 'cursor-home-passthrough';

  @override
  Future<void> afterManifestFlush(PostManifestFlushContext ctx) async {
    final memberHome = ctx.environment['HOME']?.trim() ?? '';
    final realHome = ctx.workHome.trim();
    if (memberHome.isEmpty || realHome.isEmpty || memberHome == realHome) {
      return;
    }

    ctx.reportDetail?.call(progressDetail);
    final started = DateTime.now();
    final runner = ctx.remoteRunner;

    if (runner != null) {
      final script = CursorMemberHomePassthrough.buildRemoteMirrorScript(
        realHomeRoot: realHome,
        memberHomeRoot: memberHome,
      );
      if (script.isEmpty) return;
      appLogger.d(
        '[session-launch] cursor home passthrough via ssh begin '
        'realHome=$realHome',
      );
      await runner.runScript(
        script,
        operation: 'Cursor home passthrough',
      );
      appLogger.d(
        '[session-launch] cursor home passthrough via ssh done '
        'ms=${DateTime.now().difference(started).inMilliseconds}',
      );
      return;
    }

    appLogger.d(
      '[session-launch] cursor home passthrough begin realHome=$realHome',
    );
    await CursorMemberHomePassthrough(fs: ctx.workFs).mirror(
      realHomeRoot: realHome,
      memberHomeRoot: memberHome,
    );
    appLogger.d(
      '[session-launch] cursor home passthrough done '
      'ms=${DateTime.now().difference(started).inMilliseconds}',
    );
  }
}
