import '../../models/cli_preset.dart';
import '../../models/landing_launch_context.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/home_workspace/landing_prefs_store.dart';

/// True when [draft] uses explicit Simple custom cli/provider/model/effort.
bool landingDraftIsCustom(LandingLaunchContext draft) =>
    draft.isPersonal && draft.cli != null;

/// Landing Simple submit: preset wins; otherwise explicit four-tuple / defaults.
SimpleLaunchIdentity resolveLandingSimpleLaunchIdentity({
  required List<CliPreset> presets,
  String? presetId,
  CliTool? cli,
  String? provider,
  String? model,
  String? effort,
  String? expertKey,
}) {
  final trimmedPresetId = presetId?.trim() ?? '';
  final preset = trimmedPresetId.isEmpty
      ? null
      : presetById(trimmedPresetId, presets);
  if (preset != null) {
    return SimpleLaunchIdentity.resolve(
      preset: preset,
      presetId: presetId,
      expertKey: expertKey,
    );
  }
  return SimpleLaunchIdentity.resolve(
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
    presetId: '',
    expertKey: expertKey,
  );
}

/// Select a global preset and clear any custom four-tuple.
LandingLaunchContext landingDraftSelectingPreset(
  LandingLaunchContext draft,
  String presetId,
) {
  return draft.copyWith(
    presetId: presetId,
    cli: null,
    provider: null,
    model: null,
    effort: null,
  );
}

/// Confirm custom launch and clear preset provenance.
LandingLaunchContext landingDraftSelectingCustom(
  LandingLaunchContext draft, {
  required CliTool cli,
  required String provider,
  required String model,
  required String effort,
}) {
  return draft.copyWith(
    presetId: null,
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
  );
}

/// Loads persisted compose-landing draft for a workspace (local to landing UI).
///
/// When no workspace prefs exist, [simpleModeDefaultFullAccess] seeds the
/// permission chip (app Session setting; defaults to full access).
Future<LandingLaunchContext> resolveLandingDraft({
  required String workspaceId,
  LandingPrefsStore? store,
  bool simpleModeDefaultFullAccess = true,
}) async {
  final prefs = await (store ?? LandingPrefsStore()).prefsFor(workspaceId);
  if (prefs == null) {
    return LandingLaunchContext(
      isPersonal: true,
      dangerouslySkipPermissions: simpleModeDefaultFullAccess,
    );
  }
  return LandingLaunchContext(
    isPersonal: prefs.isPersonal,
    presetId: prefs.presetId,
    teamId: prefs.teamId,
    projectFolderPath: prefs.projectFolderPath,
    expertKey: prefs.expertKey,
    workingDirectoryPath: prefs.workingDirectoryPath,
    dangerouslySkipPermissions: prefs.dangerouslySkipPermissions,
    cli: prefs.cli,
    provider: prefs.provider,
    model: prefs.model,
    effort: prefs.effort,
  );
}

Future<void> persistLandingDraft(
  String workspaceId,
  LandingLaunchContext draft, {
  LandingPrefsStore? store,
}) {
  return (store ?? LandingPrefsStore()).save(
    workspaceId,
    LandingPrefs(
      isPersonal: draft.isPersonal,
      presetId: draft.presetId,
      teamId: draft.teamId,
      projectFolderPath: draft.projectFolderPath,
      expertKey: draft.expertKey,
      workingDirectoryPath: draft.workingDirectoryPath,
      dangerouslySkipPermissions: draft.dangerouslySkipPermissions,
      cli: draft.cli,
      provider: draft.provider,
      model: draft.model,
      effort: draft.effort,
    ),
  );
}
