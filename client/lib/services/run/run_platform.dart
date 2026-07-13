import '../../models/run/launch_configuration.dart';
import '../../models/run/launch_type_contribution.dart';
import '../../models/run/run_session.dart';
import '../../models/workspace_folder.dart';
import 'launch_adapter_client.dart';
import 'launch_adapter_protocol.dart';
import 'launch_config_store.dart';
import 'launch_discover.dart';
import 'launch_type_normalize.dart';
import 'launch_type_registrar.dart';
import 'launch_type_registry.dart';
import 'launch_type_unavailable.dart';
import 'launch_variable_expander.dart';
import 'run_session_manager.dart';
import 'shell_script_launch_schema.dart';

/// Platforms that bind asynchronously (e.g. workspace tab scope) expose [whenReady].
abstract mixin class RunPlatformDeferred {
  Future<void> get whenReady;
}

/// Completes immediately for eager platforms; awaits deferred initialization otherwise.
Future<void> whenRunPlatformReady(RunPlatformApi platform) {
  if (platform is RunPlatformDeferred) {
    return (platform as RunPlatformDeferred).whenReady;
  }
  return Future<void>.value();
}

/// Narrow surface [RunCubit] uses — concrete [RunPlatform] or test fakes.
abstract class RunPlatformApi {
  RunSessionManager get sessionManager;

  Future<List<OwnedLaunchConfiguration>> listConfigurations(
    List<WorkspaceFolder> folders,
  );

  Future<List<OwnedLaunchCompound>> listCompounds(
    List<WorkspaceFolder> folders,
  );

  Stream<List<RunSession>> get sessionsStream;

  List<RunSession> get sessions;

  Stream<List<LaunchAdapterConfigurationEntry>> get actionsStream;

  Future<List<LaunchOption>> provideOptions(OwnedLaunchConfiguration owned);

  Stream<List<LaunchOption>> optionsChangedFor(OwnedLaunchConfiguration owned);

  List<String> validateConfiguration(OwnedLaunchConfiguration owned);

  Future<RunSession> start(OwnedLaunchConfiguration owned);

  Future<List<String>> startCompound({
    required OwnedLaunchCompound owned,
    required List<OwnedLaunchConfiguration> documentConfigs,
  });

  Future<void> stop(String sessionId);

  Future<RunSession> restart(String sessionId);

  Future<void> stopCompound(List<String> sessionIds);

  Future<ConfigureActionResult> configureAction({
    required String actionId,
    required String workspaceFolder,
    required Map<String, Object?> result,
    required String type,
    String targetId = WorkspaceFolder.localTargetId,
  });

  Future<void> persistConfiguration({
    required WorkspaceFolder folder,
    required LaunchConfiguration configuration,
  });

  Future<void> deleteConfiguration({
    required WorkspaceFolder folder,
    required String id,
  });

  String launchJsonPath(WorkspaceFolder folder);

  Future<void> rebuildLaunchTypes();

  Future<List<OwnedLaunchConfiguration>> discoverRecommendations(
    List<WorkspaceFolder> folders, {
    List<OwnedLaunchConfiguration> existing = const [],
  });

  /// Whether [type] can run on [targetId] (built-in `shellScript` always true).
  bool isTypeAvailable(String type, {required String targetId});

  /// Human-readable reason when [isTypeAvailable] is false; null when available.
  String? unavailableReason(String type, {required String targetId});

  /// JSON-schema map for [type], or null when the type is unknown.
  Map<String, Object?>? configurationSchema(String type);

  /// Capability kinds for [type] (e.g. `run`, `debug`, `build`).
  ///
  /// Unknown types default to `['run']` so the toolbar stays Run-only.
  List<String> kindsFor(String type);

  /// Registered launch types for the Add-configuration type picker.
  List<LaunchTypeContribution> get launchTypes;
}

/// Facade wiring store, registry, session manager, adapter client, registrar.
class RunPlatform implements RunPlatformApi {
  RunPlatform({
    required this.store,
    required this.registry,
    required this.sessionManager,
    required this.adapterClient,
    required this.registrar,
  });

  final LaunchConfigStore store;
  final LaunchTypeRegistry registry;
  @override
  final RunSessionManager sessionManager;
  final LaunchAdapterClient adapterClient;
  final LaunchTypeRegistrar registrar;

  @override
  Future<List<OwnedLaunchConfiguration>> listConfigurations(
    List<WorkspaceFolder> folders,
  ) => store.listConfigurations(folders: folders);

  @override
  Future<List<OwnedLaunchCompound>> listCompounds(
    List<WorkspaceFolder> folders,
  ) => store.listCompounds(folders: folders);

  @override
  Stream<List<RunSession>> get sessionsStream => sessionManager.sessionsStream;

  @override
  List<RunSession> get sessions => sessionManager.sessions;

  @override
  Stream<List<LaunchAdapterConfigurationEntry>> get actionsStream =>
      adapterClient.configurationsChanged.map((e) => e.configurations);

  @override
  Future<List<LaunchOption>> provideOptions(
    OwnedLaunchConfiguration owned,
  ) async {
    final type = normalizeLaunchType(owned.configuration.type);
    if (isBuiltInShellType(type)) return const [];

    final contribution = registry.get(type);
    if (contribution == null || contribution.extensionId == null) {
      return const [];
    }

    await adapterClient.initialize(
      type: contribution.type,
      targetId: owned.owner.targetId,
      adapterCommand: contribution.adapterCommand,
      extensionId: contribution.extensionId,
      lifecycle: contribution.lifecycle,
    );

    return adapterClient.provideOptions(
      configurationId: owned.configId,
      configuration: owned.configuration.toJson(),
      type: type,
      targetId: owned.owner.targetId,
    );
  }

  @override
  Stream<List<LaunchOption>> optionsChangedFor(
    OwnedLaunchConfiguration owned,
  ) {
    final type = owned.configuration.type;
    final targetId = owned.owner.targetId;
    return adapterClient.optionsChanged
        .where((e) => e.type == type && e.targetId == targetId)
        .map((e) => e.options);
  }

  @override
  List<String> validateConfiguration(OwnedLaunchConfiguration owned) {
    final type = normalizeLaunchType(owned.configuration.type);
    final targetId = owned.owner.targetId;
    if (isBuiltInShellType(type)) {
      final expanded = LaunchVariableExpander.expandConfiguration(
        owned.configuration.copyWith(type: type),
        workspaceFolder: owned.owner.path,
        env: owned.configuration.env,
      );
      return ShellScriptLaunchSchema.validate(expanded);
    }
    final contribution = registry.get(type);
    if (contribution == null) {
      return ['unregistered launch type: $type'];
    }
    if (!registry.isAvailable(type, targetId: targetId)) {
      return ['launch type $type is not available on target $targetId'];
    }
    return validateAgainstSchema(
      owned.configuration.toJson(),
      contribution.configurationSchema,
    );
  }

  @override
  Future<RunSession> start(OwnedLaunchConfiguration owned) async {
    final errors = validateConfiguration(owned);
    if (errors.isNotEmpty) {
      throw StateError(errors.join('; '));
    }
    return sessionManager.start(owned);
  }

  @override
  Future<List<String>> startCompound({
    required OwnedLaunchCompound owned,
    required List<OwnedLaunchConfiguration> documentConfigs,
  }) {
    return sessionManager.startCompound(
      compound: owned.compound,
      documentConfigs: documentConfigs,
    );
  }

  @override
  Future<void> stop(String sessionId) => sessionManager.stop(sessionId);

  @override
  Future<RunSession> restart(String sessionId) =>
      sessionManager.restart(sessionId);

  @override
  Future<void> stopCompound(List<String> sessionIds) =>
      sessionManager.stopCompound(sessionIds);

  @override
  Future<ConfigureActionResult> configureAction({
    required String actionId,
    required String workspaceFolder,
    required Map<String, Object?> result,
    required String type,
    String targetId = WorkspaceFolder.localTargetId,
  }) {
    return adapterClient.configureAction(
      type: type,
      actionId: actionId,
      workspaceFolder: workspaceFolder,
      result: result,
      targetId: targetId,
    );
  }

  @override
  Future<void> persistConfiguration({
    required WorkspaceFolder folder,
    required LaunchConfiguration configuration,
  }) {
    final errors = validateConfiguration(
      OwnedLaunchConfiguration(owner: folder, configuration: configuration),
    );
    if (errors.isNotEmpty) {
      throw StateError(errors.join('; '));
    }
    return store.upsertConfiguration(
      folder: folder,
      configuration: configuration,
    );
  }

  @override
  Future<void> deleteConfiguration({
    required WorkspaceFolder folder,
    required String id,
  }) {
    return store.deleteConfiguration(folder: folder, id: id);
  }

  @override
  String launchJsonPath(WorkspaceFolder folder) =>
      LaunchConfigStore.launchConfigPath(folder);

  @override
  Future<void> rebuildLaunchTypes() => registrar.rebuild(registry);

  @override
  Future<List<OwnedLaunchConfiguration>> discoverRecommendations(
    List<WorkspaceFolder> folders, {
    List<OwnedLaunchConfiguration> existing = const [],
  }) {
    return LaunchDiscover(io: store.io).discover(
      folders: folders,
      registry: registry,
      existing: existing,
    );
  }

  @override
  bool isTypeAvailable(String type, {required String targetId}) =>
      registry.isAvailable(normalizeLaunchType(type), targetId: targetId);

  @override
  String? unavailableReason(String type, {required String targetId}) {
    return launchTypeUnavailableCode(
      registry,
      type: normalizeLaunchType(type),
      targetId: targetId,
    );
  }

  @override
  Map<String, Object?>? configurationSchema(String type) {
    final normalized = normalizeLaunchType(type);
    if (isBuiltInShellType(normalized)) {
      return Map<String, Object?>.from(
        ShellScriptLaunchSchema.configurationSchema,
      );
    }
    final contribution = registry.get(normalized);
    if (contribution == null) return null;
    return Map<String, Object?>.from(contribution.configurationSchema);
  }

  @override
  List<String> kindsFor(String type) {
    final contribution = registry.get(normalizeLaunchType(type));
    if (contribution == null) return const ['run'];
    return List<String>.from(contribution.kinds);
  }

  @override
  List<LaunchTypeContribution> get launchTypes => registry.contributions.toList();
}

/// Minimal JSON Schema `required` / property-type checks for launch configs.
List<String> validateAgainstSchema(
  Map<String, Object?> configuration,
  Map<String, Object?> schema,
) {
  final errors = <String>[];
  final required = schema['required'];
  if (required is List) {
    for (final key in required) {
      final name = key.toString();
      final value = configuration[name];
      if (value == null || (value is String && value.trim().isEmpty)) {
        errors.add('$name is required');
      }
    }
  }

  final properties = schema['properties'];
  if (properties is Map) {
    for (final entry in properties.entries) {
      final key = entry.key.toString();
      final propSchema = entry.value;
      if (propSchema is! Map) continue;
      final value = configuration[key];
      if (value == null) continue;
      final expected = propSchema['type']?.toString();
      if (expected == null) continue;
      final ok = switch (expected) {
        'string' => value is String,
        'boolean' => value is bool,
        'array' => value is List,
        'object' => value is Map,
        'number' || 'integer' => value is num,
        _ => true,
      };
      if (!ok) {
        errors.add('$key must be a $expected');
      }
    }
  }
  return errors;
}
