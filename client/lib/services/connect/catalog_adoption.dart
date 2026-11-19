import '../../models/connection/catalog_entry.dart';
import '../../models/connection/machine_id.dart';
import '../../repositories/catalog_store.dart';
import '../../repositories/connection_store.dart';
import '../../utils/logging/logger.dart';
import 'profile_connection_mapping.dart';

/// Converts a schema-1 plane catalog into the current model, exactly once.
///
/// Schema 1 kept the address on the plane, so those rows were the only way a
/// device could reach a machine it had never paired with. Moving the address
/// off the plane therefore has to **seed a device connection** from every
/// legacy row first; otherwise the machine would keep existing in the catalog
/// but become unreachable from this device.
///
/// Idempotent: seeding skips machines that already have a connection, and the
/// rewrite removes the legacy shape, so a second call is a pure read.
Future<({List<CatalogEntry> entries, int seeded})> adoptCatalog({
  required CatalogStore catalog,
  required ConnectionStore connections,
}) async {
  final snapshot = await catalog.readSnapshot();
  if (snapshot == null) return (entries: const <CatalogEntry>[], seeded: 0);
  if (!snapshot.legacy) return (entries: snapshot.entries, seeded: 0);

  final existing = await connections.loadAll();
  final known = {for (final connection in existing) connection.machineId};
  final seeded = [...existing];
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final row in snapshot.legacyRows) {
    final machineId = MachineId(row.id);
    if (machineId.isEmpty || known.contains(machineId)) continue;
    if (row.host.trim().isEmpty && row.endpoints.isEmpty) continue;
    seeded.add(connectionFromProfile(row, updatedAt: now));
    known.add(machineId);
  }
  final seededCount = seeded.length - existing.length;
  if (seededCount > 0) {
    await connections.saveAll(seeded);
  }

  final adopted = [
    for (final entry in snapshot.entries)
      if (entry.machineId.isNotEmpty) entry,
  ];
  await catalog.saveAll(adopted);
  AppLogger.instance.i(
    '[catalog] adopted schema 1: ${adopted.length} entries, '
    '$seededCount connections seeded',
  );
  return (entries: adopted, seeded: seededCount);
}
