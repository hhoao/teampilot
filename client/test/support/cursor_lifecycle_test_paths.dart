import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_context.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

/// Minimal [ConfigProfileDelegate] for cursor lifecycle unit tests.
final class CursorLifecycleTestPaths implements ConfigProfileDelegate {
  CursorLifecycleTestPaths({required this.fs, required this.layout});

  @override
  final Filesystem fs;

  @override
  final RuntimeLayout layout;

  @override
  String get basePath => layout.teampilotRoot;

  @override
  String get home => '/home/user';

  @override
  p.Context get pathContext => fs.pathContext;

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

  @override
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  ) async =>
      Map<String, Object?>.from(defaults);

  @override
  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value) async {}

  @override
  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required Iterable<String> directories,
  }) async =>
      defaultMetadata;

  @override
  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories, {
    required Map<String, Object?> defaultMetadata,
  }) async =>
      false;

  @override
  Future<Map<String, Object?>> readSettingsFile(String path) async => {};

  @override
  Future<void> writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
    required String tool,
    String? teamId,
    String? workspaceId,
  }) async {}

  @override
  Future<bool> hasEnabledExtensionSettingsHooks(
    String tool, {
    String? teamId,
    String? workspaceId,
  }) async =>
      false;

  @override
  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? workspaceId,
  }) async =>
      settings;

  @override
  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  }) async =>
      settings;

  @override
  HostExecutionEnvironment hostEnvironmentForProvision() =>
      HostExecutionEnvironment.resolve();
}
