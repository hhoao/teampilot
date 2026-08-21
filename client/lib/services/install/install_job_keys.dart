import '../../models/install_job/install_job_key.dart';
import '../../models/install_job/install_job_scope.dart';

abstract final class InstallJobKeys {
  static InstallJobKey cli(String cliValue, {required InstallJobScope scope}) =>
      InstallJobKey(
        kind: InstallJobKind.cliExecutable,
        target: cliValue,
        scope: scope,
      );

  static InstallJobKey toolchain(
    String toolId, {
    required InstallJobScope scope,
  }) => InstallJobKey(
    kind: InstallJobKind.toolchain,
    target: toolId,
    scope: scope,
  );

  static InstallJobKey skill(String skillId) => InstallJobKey(
    kind: InstallJobKind.packAcquire,
    target: 'skill:$skillId',
  );

  static InstallJobKey plugin(String pluginId) => InstallJobKey(
    kind: InstallJobKind.packAcquire,
    target: 'plugin:$pluginId',
  );

  static InstallJobKey extension(String extId) => InstallJobKey(
    kind: InstallJobKind.packAcquire,
    target: 'extension:$extId',
  );

  static InstallJobKey hubTeam(String hubKey) => InstallJobKey(
    kind: InstallJobKind.hubClone,
    target: 'team:$hubKey',
  );

  static InstallJobKey hubExpert(String hubKey) => InstallJobKey(
    kind: InstallJobKind.hubClone,
    target: 'expert:$hubKey',
  );

  static InstallJobKey fileImport(String workspaceId, String planHash) =>
      InstallJobKey(
        kind: InstallJobKind.fileTreeImport,
        target: '$workspaceId:$planHash',
      );

  static InstallJobKey appUpdate(String version) => InstallJobKey(
    kind: InstallJobKind.appUpdate,
    target: version,
  );
}
