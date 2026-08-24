import '../../models/cli_preset.dart';
import '../../models/landing_launch_context.dart';
import '../../models/launch_security_policy.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
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
      officialProviderId: _officialProviderId,
    );
  }
  return SimpleLaunchIdentity.resolve(
    cli: cli,
    provider: provider,
    model: model,
    effort: effort,
    presetId: '',
    expertKey: expertKey,
    officialProviderId: _officialProviderId,
  );
}

String? _officialProviderId(CliTool cli) =>
    CliToolRegistry.builtIn().defaultOfficialProviderId(cli);

/// Expands [identity.presetId] into provider/model/effort when the session row
/// only persisted the preset id (landing draft, legacy rows, or silent create).
///
/// When concrete provider/model are already pinned on the session, they are kept.
SimpleLaunchIdentity enrichSimpleLaunchIdentityFromPreset({
  required SimpleLaunchIdentity identity,
  required List<CliPreset> presets,
}) {
  final presetId = identity.presetId.trim();
  if (presetId.isEmpty) return identity;
  if (identity.model.trim().isNotEmpty &&
      identity.provider.trim().isNotEmpty) {
    return identity;
  }
  final preset = presetById(presetId, presets);
  if (preset == null) return identity;
  return SimpleLaunchIdentity.resolve(
    preset: preset,
    presetId: presetId,
    cli: identity.cli,
    expertKey: identity.expertKey,
    officialProviderId: _officialProviderId,
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

/// When [draft] is personal with no preset and no custom launch, pick [presets].first.
LandingLaunchContext seedLandingDraftPresetDefault(
  LandingLaunchContext draft,
  List<CliPreset> presets,
) {
  if (!draft.isPersonal) return draft;
  if (draft.presetId?.trim().isNotEmpty == true) return draft;
  if (draft.cli != null) return draft;
  final first = presets.firstOrNull;
  if (first == null) return draft;
  return landingDraftSelectingPreset(draft, first.id);
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
      launchSecurityPolicy: simpleModeDefaultFullAccess
          ? LaunchSecurityPolicy.fullAccess
          : LaunchSecurityPolicy.cliDefault,
    );
  }
  return LandingLaunchContext(
    isPersonal: prefs.isPersonal,
    presetId: prefs.presetId,
    teamId: prefs.teamId,
    projectFolderPath: prefs.projectFolderPath,
    expertKey: prefs.expertKey,
    workingDirectoryPath: prefs.workingDirectoryPath,
    launchSecurityPolicy: prefs.launchSecurityPolicy,
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
      launchSecurityPolicy: draft.launchSecurityPolicy,
      cli: draft.cli,
      provider: draft.provider,
      model: draft.model,
      effort: draft.effort,
    ),
  );
}
