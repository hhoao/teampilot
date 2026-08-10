import '../../../io/filesystem.dart';
import '../../registry/capabilities/remote_app_data_capability.dart';

final class NoRemoteAppData implements RemoteAppDataCapability {
  const NoRemoteAppData();
  @override bool get needsSharedPluginDepsBeforeReconcile => false;
  @override Future<void> seedSharedPluginDeps({Filesystem? homeFs, String? homeRoot}) async {}
}
