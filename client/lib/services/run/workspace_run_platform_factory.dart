import '../../models/extension_manifest.dart';
import '../../repositories/extension_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../extension/extension_detector.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'launch_adapter_client.dart';
import 'launch_config_store.dart';
import 'launch_type_registrar.dart';
import 'launch_type_registry.dart';
import 'run_platform.dart';
import 'run_session_manager.dart';

/// Builds a per-workspace [RunPlatform] with extension enablement injected.
///
/// Enablement reuses [ExtensionRepository] +
/// [WorkspaceProjectConfig.effectiveExtensionEnabled] (same chain as
/// [SessionLifecycleService.loadEnabledExtensionIds]).
class WorkspaceRunPlatformFactory {
  WorkspaceRunPlatformFactory({
    required ExtensionRepository extensionRepository,
    required WorkspaceProjectConfigRepository projectConfigRepository,
    Filesystem? fs,
    ExtensionDetector? detector,
    String Function(String extensionId)? extensionPathFor,
  }) : _extensionRepository = extensionRepository,
       _projectConfigRepository = projectConfigRepository,
       _fs = fs,
       _detector = detector ?? ExtensionDetector(),
       _extensionPathFor = extensionPathFor;

  final ExtensionRepository _extensionRepository;
  final WorkspaceProjectConfigRepository _projectConfigRepository;
  final Filesystem? _fs;
  final ExtensionDetector _detector;
  final String Function(String extensionId)? _extensionPathFor;

  Filesystem get _filesystem => _fs ?? AppStorage.fs;

  Future<RunPlatform> create({required String workspaceId}) async {
    final enabled = await _loadEnabledManifests(workspaceId);
    final pathFor = _extensionPathFor ?? _resolveExtensionPath;
    final registry = LaunchTypeRegistry.withBuiltIns();
    final registrar = LaunchTypeRegistrar.withExtensionDetector(
      extensions: enabled,
      detector: _detector,
      extensionPathFor: pathFor,
    );
    final adapterClient = LaunchAdapterClient(
      extensionPathResolver: pathFor,
    );
    final store = LaunchConfigStore(
      io: FilesystemLaunchConfigIo(_filesystem),
    );
    final sessionManager = RunSessionManager(
      launchAdapterClient: adapterClient,
      resolveLaunchType: registry.get,
    );
    final platform = RunPlatform(
      store: store,
      registry: registry,
      sessionManager: sessionManager,
      adapterClient: adapterClient,
      registrar: registrar,
    );
    await platform.rebuildLaunchTypes();
    return platform;
  }

  String _resolveExtensionPath(String extensionId) {
    final ctx = _filesystem.pathContext;
    return ctx.join(AppStorage.paths.basePath, 'extensions', extensionId);
  }

  Future<List<ExtensionManifest>> _loadEnabledManifests(
    String workspaceId,
  ) async {
    final trimmed = workspaceId.trim();
    final global = (await _extensionRepository.load()).globalEnabled;
    if (trimmed.isEmpty) {
      return [
        for (final manifest in _extensionRepository.manifests)
          if (global.contains(manifest.id)) manifest,
      ];
    }
    final config = await _projectConfigRepository.load(trimmed);
    return [
      for (final manifest in _extensionRepository.manifests)
        if (config.effectiveExtensionEnabled(
          extensionId: manifest.id,
          globalEnabled: global,
        ))
          manifest,
    ];
  }
}
