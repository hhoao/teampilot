import '../../models/extension_manifest.dart';
import '../../models/run/run_ui_intent.dart';
import '../../models/ssh_profile.dart';
import '../../models/workspace_folder.dart';
import '../../repositories/extension_repository.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../../repositories/workspace_project_config_repository.dart';
import '../extension/extension_detector.dart';
import '../io/filesystem.dart';
import '../ssh/ssh_client_factory.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_context.dart';
import '../terminal/workspace_terminal_run_service.dart';
import 'launch_adapter_client.dart';
import 'launch_config_store.dart';
import 'launch_type_registrar.dart';
import 'launch_type_registry.dart';
import 'process_run_executor.dart';
import 'run_platform.dart';
import 'run_session_manager.dart';
import 'shell_script_launcher.dart';

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
    Future<RuntimeContext> Function(String targetId)? resolveWorkContext,
    SshProfileRepository? sshProfileRepository,
    SshClientFactory? sshClientFactory,
    TerminalRunDepsResolver? terminalRunDeps,
  }) : _extensionRepository = extensionRepository,
       _projectConfigRepository = projectConfigRepository,
       _fs = fs,
       _detector = detector ?? ExtensionDetector(),
       _extensionPathFor = extensionPathFor,
       _resolveWorkContext = resolveWorkContext,
       _sshProfileRepository = sshProfileRepository,
       _sshClientFactory = sshClientFactory,
       terminalRunDeps = terminalRunDeps ?? TerminalRunDepsResolver();

  final ExtensionRepository _extensionRepository;
  final WorkspaceProjectConfigRepository _projectConfigRepository;
  final Filesystem? _fs;
  final ExtensionDetector _detector;
  final String Function(String extensionId)? _extensionPathFor;
  final Future<RuntimeContext> Function(String targetId)? _resolveWorkContext;
  final SshProfileRepository? _sshProfileRepository;
  final SshClientFactory? _sshClientFactory;

  /// Filled after [WorkspaceShellConnector] exists (see app_shell bootstrap).
  final TerminalRunDepsResolver terminalRunDeps;

  Filesystem get _filesystem => _fs ?? AppStorage.fs;

  Future<RunPlatform> create({
    required String workspaceId,
    void Function(RunUiIntent intent)? emitUiIntent,
  }) async {
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
      io: TargetAwareLaunchConfigIo(resolveFilesystem: _filesystemForTarget),
    );
    final executor = ProcessRunExecutor(sshSpawner: _sshSpawner);
    final sessionManager = RunSessionManager(
      executor: RunShellScriptLauncher(
        workspaceId: workspaceId,
        terminalRunDeps: terminalRunDeps,
        processExecutor: executor,
        emitUiIntent: emitUiIntent,
      ),
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

  Future<Filesystem> _filesystemForTarget(String targetId) async {
    final resolver = _resolveWorkContext;
    if (resolver == null ||
        targetId == WorkspaceFolder.localTargetId ||
        targetId.trim().isEmpty) {
      return _filesystem;
    }
    final ctx = await resolver(targetId);
    return ctx.filesystem;
  }

  Future<ProcessRunHandle> _sshSpawner({
    required String sshProfileId,
    required String shellCommand,
  }) async {
    final profiles = _sshProfileRepository;
    final factory = _sshClientFactory;
    if (profiles == null || factory == null) {
      throw StateError('SSH process execution is not configured');
    }
    final SshProfile? profile = await profiles.findById(sshProfileId);
    if (profile == null) {
      throw StateError('SSH profile not found for this run target');
    }
    final client = await factory.clientForStorage(profile);
    final session = await client.execute(shellCommand);
    return SshProcessRunHandle(session);
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
