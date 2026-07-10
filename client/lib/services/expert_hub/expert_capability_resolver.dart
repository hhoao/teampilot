import '../../cubits/expert_hub_cubit.dart';
import '../../models/config_bundle.dart';
import '../../models/discoverable_member.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../team/team_clone_service.dart';
import 'composite_expert_hub_source.dart';
import 'expert_capability_pack.dart';
import 'expert_member_materializer.dart';
import 'expert_member_resolver.dart';
import 'local_member_template_store.dart';

/// Resolves an expert into a capability pack (persona + installed deps).
///
/// Installs skill/plugin/MCP deps into the **app global library** only.
/// Per-dep failures are soft (listed in [ExpertCapabilityPack.failedDeps]);
/// a missing expert key is a hard fail (`null` from key-based APIs).
class ExpertCapabilityResolver {
  ExpertCapabilityResolver({
    required SkillDepInstaller installSkill,
    required PluginDepInstaller installPlugin,
    required McpDepInstaller installMcp,
    CompositeExpertHubSource? source,
    LocalMemberTemplateStore? localStore,
    ExpertHubCubit? cubit,
  }) : _installSkill = installSkill,
       _installPlugin = installPlugin,
       _installMcp = installMcp,
       _source = source,
       _localStore = localStore,
       _cubit = cubit;

  final SkillDepInstaller _installSkill;
  final PluginDepInstaller _installPlugin;
  final McpDepInstaller _installMcp;
  final CompositeExpertHubSource? _source;
  final LocalMemberTemplateStore? _localStore;
  ExpertHubCubit? _cubit;

  /// Late-bind hub cubit after bootstrap constructs [ExpertHubCubit].
  void attachHubCubit(ExpertHubCubit cubit) => _cubit = cubit;

  /// Resolve catalog key → pack (install deps). Returns null if expert not found.
  Future<ExpertCapabilityPack?> resolveKey(
    String expertKey, {
    TeamRosterSlotOverrides? overrides,
    TeamProfile? team,
    String? slotId,
    int? joinedAt,
  }) async {
    final expert = await ExpertMemberResolver.resolveMember(
      key: expertKey,
      hubState: _cubit?.state,
      source: _source,
      localStore: _localStore,
      cubit: _cubit,
    );
    if (expert == null) return null;
    return resolve(
      expert,
      overrides: overrides,
      team: team,
      slotId: slotId,
      joinedAt: joinedAt,
    );
  }

  /// Resolve already-loaded member → pack.
  Future<ExpertCapabilityPack> resolve(
    DiscoverableMember expert, {
    TeamRosterSlotOverrides? overrides,
    TeamProfile? team,
    String? slotId,
    int? joinedAt,
  }) async {
    final failed = <DependencyFailure>[];
    final skillIds = <String>[];
    for (final dep in expert.skillDeps) {
      final id = await _installSkill(dep);
      if (id != null) {
        skillIds.add(id);
      } else {
        failed.add(DependencyFailure(DependencyKind.skill, dep.name));
      }
    }

    final pluginIds = <String>[];
    for (final dep in expert.pluginDeps) {
      final id = await _installPlugin(dep);
      if (id != null) {
        pluginIds.add(id);
      } else {
        failed.add(DependencyFailure(DependencyKind.plugin, dep.name));
      }
    }

    final mcpServerIds = <String>[];
    for (final dep in expert.mcpDeps) {
      final id = await _installMcp(dep);
      if (id != null) {
        mcpServerIds.add(id);
      } else {
        failed.add(DependencyFailure(DependencyKind.mcp, dep.name));
      }
    }

    final bundle = ConfigBundle(
      skillIds: skillIds,
      pluginIds: pluginIds,
      mcpServerIds: mcpServerIds,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    final TeamMemberConfig member;
    if (team != null) {
      member = ExpertMemberMaterializer.materializeRosterSlot(
        slot: TeamRosterSlot(
          id: slotId ?? expert.member.name,
          expertKey: expert.key,
          overrides: overrides ?? const TeamRosterSlotOverrides(),
          joinedAt: joinedAt ?? now,
        ),
        expert: expert,
        team: team,
        joinedAtOverride: joinedAt,
      );
    } else {
      member = expert.toMemberConfig(joinedAt: joinedAt ?? now);
    }

    return ExpertCapabilityPack(
      member: member,
      bundle: bundle,
      failedDeps: failed,
    );
  }

  /// Same as [resolveKey] but intended for early install (Landing select /
  /// add-to-team). Returns null if the expert key is unknown.
  Future<ExpertCapabilityPack?> preflight(String expertKey) =>
      resolveKey(expertKey);
}
