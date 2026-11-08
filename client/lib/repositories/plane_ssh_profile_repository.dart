import '../models/ssh_profile.dart';
import '../models/ssh_server_profile.dart';
import 'remote_target_repository.dart';
import 'ssh_profile_repository.dart';
import 'ssh_server_profile_repository.dart';

/// [SshProfileRepository] over the shared home-plane server catalog.
///
/// Reads merge the plane's own `remote-targets.json` with the synced
/// `ssh_profiles/profiles.json`; writes go to the projection, the record every
/// device paired to the plane shares. Profile selection stays a device concern,
/// so it is never persisted on the plane.
///
/// This is what the "SSH servers" settings surface binds to, which keeps that
/// page showing the plane's servers rather than this device's targets.
class PlaneSshProfileRepository extends SshProfileRepository {
  PlaneSshProfileRepository({
    required super.storage,
    required SshServerProfileRepository servers,
    RemoteTargetRepository? deviceTargets,
  }) : _servers = servers,
       _deviceTargets = deviceTargets;

  final SshServerProfileRepository _servers;

  /// This device's connection catalog, used only to lend the matching server's
  /// vault reference to the plane projection. It is never written to the plane.
  final RemoteTargetRepository? _deviceTargets;

  @override
  Future<List<SshProfile>> loadAll() async {
    final vaultRefs = await _deviceVaultRefs();
    return [
      for (final server in await _servers.loadAll())
        _toProfile(server, vaultEntryId: vaultRefs[server.id]),
    ];
  }

  /// The plane record cannot carry a credential reference, so the matching
  /// device target lends its own. A device that never connected to a server has
  /// no entry and therefore no reference, which is the correct answer there.
  Future<Map<String, String>> _deviceVaultRefs() async {
    final device = _deviceTargets;
    if (device == null) return const {};
    final refs = <String, String>{};
    for (final target in await device.loadAll()) {
      final entryId = target.vaultEntryId?.trim() ?? '';
      if (entryId.isNotEmpty) refs[target.id] = entryId;
    }
    return refs;
  }

  @override
  Future<SshProfile?> findById(String profileId) async {
    for (final profile in await loadAll()) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  @override
  Future<void> save(SshProfile profile) => _servers.save(_toServer(profile));

  @override
  Future<void> saveAll(List<SshProfile> profiles) async {
    for (final profile in profiles) {
      await _servers.save(_toServer(profile));
    }
  }

  @override
  Future<void> delete(String profileId) => _servers.delete(profileId);

  @override
  Future<String> loadSelectedProfileId() async => '';

  @override
  Future<void> saveSelectedProfileId(String profileId) async {}

  static SshProfile _toProfile(
    SshServerProfile server, {
    String? vaultEntryId,
  }) => SshProfile(
    id: server.id,
    name: server.name,
    host: server.host,
    port: server.port,
    username: server.username,
    authType: server.authType,
    createdAt: server.updatedAt,
    updatedAt: server.updatedAt,
    embeddedTarget: server.embeddedTarget,
    relayUrl: server.relayUrl,
    pairedDesktopId: server.pairedDesktopId,
    vaultEntryId: vaultEntryId,
  );

  static SshServerProfile _toServer(SshProfile profile) => SshServerProfile(
    id: profile.id,
    name: profile.name,
    host: profile.host,
    port: profile.port,
    username: profile.username,
    authType: profile.authType,
    embeddedTarget: profile.embeddedTarget,
    relayUrl: profile.relayUrl,
    pairedDesktopId: profile.pairedDesktopId,
    updatedAt: profile.updatedAt,
  );
}
