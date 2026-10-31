import '../../../../models/app_provider_config.dart';
import '../../../../models/team_config.dart';
import '../../../../repositories/app_provider_repository.dart';
import '../../../storage/home_storage.dart';
import '../opencode_config.dart';
import '../opencode_go_layer.dart';
import '../provider_presets.dart';
import 'opencode_model_namespace.dart';

/// Resolves opencode providers from the app catalog for session launch.
///
/// Mirrors [CodexProviderSettingsResolver]: member binding wins, then team
/// default, then a lone provider in the catalog.
final class OpencodeProviderSettingsResolver {
  OpencodeProviderSettingsResolver({
    required String basePath,
    required HomeStorage storage,
    AppProviderRepository? repository,
  }) : _repository =
           repository ??
           AppProviderRepository(basePath: basePath, storage: storage);

  final AppProviderRepository _repository;

  Future<AppProviderConfig?> findById(String? providerId) async {
    final trimmed = providerId?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final direct = await _repository.findById(CliTool.opencode, trimmed);
    if (direct != null) return direct;
    // Model picks carry the upstream namespace (`opencode-go`), which is not a
    // catalog row: one "OpenCode" row owns both the Go and the free Zen layer.
    if (!OpencodeGoLayer.isNamespace(trimmed) &&
        trimmed != OpencodeModelNamespace.zen) {
      return null;
    }
    final providers = await _repository.loadProviders(CliTool.opencode);
    for (final provider in providers) {
      if (provider.id == OpencodeModelNamespace.zen ||
          opencodeSubscriptionKey(provider).isNotEmpty) {
        return provider;
      }
    }
    // Zen needs no configuration at all, so the preset is a usable fallback.
    return OpencodeProviderPresets.byId(OpencodeModelNamespace.zen)?.template;
  }

  Future<String?> resolveProviderId(
    TeamProfile team, {
    TeamMemberConfig? member,
  }) async {
    final fromTeam = team.providerIdsByTool['opencode']?.trim() ?? '';
    if (fromTeam.isNotEmpty) return fromTeam;

    final selected = member;
    if (selected != null && selected.isValid) {
      final fromMember = selected.provider.trim();
      if (fromMember.isNotEmpty && await findById(fromMember) != null) {
        return fromMember;
      }
    }

    for (final rosterMember in team.members) {
      final fromMember = rosterMember.provider.trim();
      if (fromMember.isEmpty) continue;
      if (await findById(fromMember) != null) return fromMember;
    }

    final providers = await _repository.loadProviders(CliTool.opencode);
    if (providers.length == 1) return providers.first.id;
    return null;
  }

  /// Provider for the process about to launch: member binding, then team default.
  Future<AppProviderConfig?> resolveForLaunch({
    required TeamProfile team,
    TeamMemberConfig? member,
  }) async {
    final selected = member;
    if (selected != null && selected.isValid) {
      final fromMember = await findById(selected.provider);
      if (fromMember != null) return fromMember;
    }

    final teamId = await resolveProviderId(team, member: member);
    if (teamId != null) return findById(teamId);

    return null;
  }

  /// The single catalogued provider, if exactly one exists (standalone default).
  Future<AppProviderConfig?> resolveSole() async {
    final providers = await _repository.loadProviders(CliTool.opencode);
    if (providers.length == 1) return providers.first;
    return null;
  }
}
