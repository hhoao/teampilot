import '../models/connection/catalog_entry.dart';
import '../models/connection/machine_id.dart';
import '../models/ssh_profile.dart';
import '../services/connect/catalog_adoption.dart';
import '../services/connect/profile_connection_mapping.dart';
import 'catalog_store.dart';
import 'ssh_profile_repository.dart';

/// The home plane's machine list, presented as profiles.
///
/// An entry only describes membership. The address, account and credential come
/// from this device's connection, so the same id cannot yield two different
/// dial plans: a machine with no local connection is simply not reachable here
/// and does not appear in this list.
class PlaneSshProfileRepository extends SshProfileRepository {
  PlaneSshProfileRepository({
    required super.storage,
    required super.connections,
    required CatalogStore catalog,
    this.onConnectionsSeeded,
  }) : _catalog = catalog;

  final CatalogStore _catalog;

  /// Fired when adopting a schema-1 catalog seeded device connections, so the
  /// device catalog can reload and make the new machines resolvable.
  final void Function()? onConnectionsSeeded;

  /// The plane's machine list, split by whether this device can reach each one.
  ///
  /// [needsConnection] is the `NeedsConnection` state: the plane says the
  /// machine exists, but this device holds no dial plan for it. It must stay
  /// visible — silently hiding those rows is how a machine disappears from the
  /// UI while still existing for every other paired device.
  Future<({List<SshProfile> reachable, List<CatalogEntry> needsConnection})>
  loadView() async {
    final entries = (await adoptCatalog(
      catalog: _catalog,
      connections: connectionStore,
    )).entries;
    final reachable = <SshProfile>[];
    final needsConnection = <CatalogEntry>[];
    if (entries.isEmpty) {
      return (reachable: reachable, needsConnection: needsConnection);
    }
    final connections = await connectionStore.loadAll();
    final byMachine = {
      for (final connection in connections) connection.machineId: connection,
    };
    for (final entry in entries) {
      final connection = byMachine[entry.machineId];
      if (connection == null) {
        needsConnection.add(entry);
        continue;
      }
      reachable.add(
        profileFromConnection(connection).copyWith(name: entry.displayName),
      );
    }
    return (reachable: reachable, needsConnection: needsConnection);
  }

  @override
  Future<List<SshProfile>> loadAll() async => (await loadView()).reachable;

  @override
  Future<SshProfile?> findById(String profileId) async {
    final entry = await _entryFor(profileId);
    if (entry == null) return null;
    final connection = await connectionStore.findById(MachineId(profileId));
    if (connection == null) return null;
    return profileFromConnection(connection).copyWith(name: entry.displayName);
  }

  /// Editing a plane row means "this machine exists here, and this device
  /// reaches it like so": membership is written to the plane, the dial plan to
  /// the device. The two never travel together again.
  @override
  Future<void> save(SshProfile profile) async {
    await _adopt();
    await _catalog.saveEntry(
      CatalogEntry(
        machineId: MachineId(profile.id),
        displayName: profile.name,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await super.save(profile);
  }

  @override
  Future<void> saveAll(List<SshProfile> profiles) async {
    for (final profile in profiles) {
      await save(profile);
    }
  }

  @override
  Future<void> delete(String profileId) async {
    await _adopt();
    await _catalog.delete(MachineId(profileId));
  }

  @override
  Future<String> loadSelectedProfileId() async => '';

  @override
  Future<void> saveSelectedProfileId(String profileId) async {}

  Future<void> _adopt() async {
    final result = await adoptCatalog(
      catalog: _catalog,
      connections: connectionStore,
    );
    if (result.seeded > 0) onConnectionsSeeded?.call();
  }

  Future<CatalogEntry?> _entryFor(String profileId) async {
    final entries = (await adoptCatalog(
      catalog: _catalog,
      connections: connectionStore,
    )).entries;
    for (final entry in entries) {
      if (entry.machineId.value == profileId) return entry;
    }
    return null;
  }
}
