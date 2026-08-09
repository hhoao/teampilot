import '../../../io/filesystem.dart';
import '../../../storage/runtime_layout.dart';
import '../../registry/capabilities/remote_app_data_capability.dart';
import '../provider/opencode_shared_plugin_deps.dart';

final class OpencodeRemoteAppData implements RemoteAppDataCapability {
  const OpencodeRemoteAppData();

  @override
  bool get needsSharedPluginDepsBeforeReconcile => true;

  @override
  Future<void> seedSharedPluginDeps({
    required Filesystem homeFs,
    required String homeRoot,
  }) async {
    final homeLayout = RuntimeLayout(
      teampilotRoot: homeRoot,
      fs: homeFs,
    );
    await OpencodeSharedPluginDeps(
      layout: homeLayout,
      fs: homeFs,
    ).ensureSharedInstalled();
  }
}
