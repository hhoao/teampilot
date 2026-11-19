import 'dart:convert';

import '../../models/connection/device_connection.dart';
import '../../models/connection/machine_id.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/connection_store.dart';
import '../io/filesystem.dart';
import '../storage/storage_failure.dart';
import '../../utils/logging/logger.dart';
import 'profile_connection_mapping.dart';

/// Outcome of the one-shot catalog upgrade.
final class ConnectionBootstrapResult {
  const ConnectionBootstrapResult({
    required this.fromLegacyProfiles,
    required this.upgraded,
    required this.skipped,
  });

  final int fromLegacyProfiles;
  final int upgraded;
  final bool skipped;
}

/// Converts every pre-v2 connection record into a [DeviceConnection] exactly
/// once, before the first catalog read of the process.
///
/// Two shapes are absorbed:
/// * `<nativeAppData>/ssh_profiles/profiles.json` — the pre-`remote-targets`
///   catalog. Relocated to `.legacy.v1` afterwards, because the home plane
///   parses that path with a reduced schema.
/// * `remote-targets.json` schema v1 — the address-row shape. Backed up to
///   `.legacy.v1` and rewritten as v2.
///
/// Transport failures propagate: a dropped link must never be mistaken for
/// "nothing to migrate". Parse failures leave the marker absent so the next
/// boot retries with the original bytes intact.
Future<ConnectionBootstrapResult> bootstrapConnections({
  required String nativeAppDataPath,
  required Filesystem localFs,
  required ConnectionStore connections,
}) async {
  final marker = localFs.pathContext.join(
    nativeAppDataPath,
    '.connection-catalog.v2',
  );
  if ((await localFs.stat(marker)).exists) {
    return const ConnectionBootstrapResult(
      fromLegacyProfiles: 0,
      upgraded: 0,
      skipped: true,
    );
  }

  final legacyFile = localFs.pathContext.join(
    nativeAppDataPath,
    'ssh_profiles',
    'profiles.json',
  );
  final legacy = <DeviceConnection>[];
  if ((await localFs.stat(legacyFile)).isFile) {
    final profiles = await _readLegacyProfiles(legacyFile, localFs);
    if (profiles == null) {
      // Unreadable: keep both the file and the absent marker, retry next boot.
      return const ConnectionBootstrapResult(
        fromLegacyProfiles: 0,
        upgraded: 0,
        skipped: false,
      );
    }
    legacy.addAll(_convert(profiles));
  }

  final current = await _readCurrent(connections);
  if (current == null) {
    // Existing rows in a shape we cannot read: never overwrite them.
    return const ConnectionBootstrapResult(
      fromLegacyProfiles: 0,
      upgraded: 0,
      skipped: false,
    );
  }
  final upgraded = await _upgradeV1Rows(connections, localFs);

  final merged = <MachineId, DeviceConnection>{
    for (final connection in current) connection.machineId: connection,
    for (final connection in upgraded) connection.machineId: connection,
    for (final connection in legacy) connection.machineId: connection,
  };
  if (merged.isNotEmpty) {
    await connections.saveAll(merged.values.toList(growable: false));
  }
  await localFs.atomicWrite(marker, '1');

  if ((await localFs.stat(legacyFile)).isFile) {
    try {
      await localFs.rename(legacyFile, '$legacyFile.legacy.v1');
    } on Object {
      // Content-free: never the caught error and never the file bytes.
      AppLogger.instance.w(
        '[connections] failed to relocate legacy profiles at $legacyFile',
      );
    }
  }

  return ConnectionBootstrapResult(
    fromLegacyProfiles: legacy.length,
    upgraded: upgraded.length,
    skipped: false,
  );
}

/// Null means "unreadable, retry later"; an empty list means "nothing stored".
Future<List<SshProfile>?> _readLegacyProfiles(
  String path,
  Filesystem fs,
) async {
  try {
    final raw = await fs.readString(path);
    if (raw == null || raw.isEmpty) return const [];
    final json = jsonDecode(raw);
    if (json is! List) return null;
    return json
        .whereType<Map<String, Object?>>()
        .map(SshProfile.fromJson)
        .toList();
  } on Object catch (error) {
    if (isStorageTransportFailure(error)) rethrow;
    AppLogger.instance.w(
      '[connections] unreadable legacy profiles at $path; keeping for retry',
    );
    return null;
  }
}

/// Reads an already-migrated v2 catalog, or an empty list when the file is
/// still v1 (the upgrade below owns it). Null means unreadable.
Future<List<DeviceConnection>?> _readCurrent(ConnectionStore store) async {
  if (!(await store.fs.stat(store.file)).isFile) return const [];
  final raw = await store.fs.readString(store.file);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final json = jsonDecode(raw);
    if (json is Map && json['schemaVersion'] == ConnectionStore.schemaVersion) {
      return await store.loadAll();
    }
    return const [];
  } on Object catch (error) {
    if (isStorageTransportFailure(error)) rethrow;
    return null;
  }
}

Future<List<DeviceConnection>> _upgradeV1Rows(
  ConnectionStore store,
  Filesystem fs,
) async {
  if (!(await fs.stat(store.file)).isFile) return const [];
  final raw = await fs.readString(store.file);
  if (raw == null || raw.isEmpty) return const [];
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on Object catch (error) {
    if (isStorageTransportFailure(error)) rethrow;
    return const [];
  }
  if (json is! List) return const [];
  final profiles = json
      .whereType<Map<String, Object?>>()
      .map(SshProfile.fromJson)
      .toList();
  // Copy before the v2 write replaces the file: a crash between the two leaves
  // the original rows recoverable.
  await fs.atomicWrite('${store.file}.legacy.v1', raw);
  return _convert(profiles);
}

List<DeviceConnection> _convert(List<SshProfile> profiles) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final result = <DeviceConnection>[];
  var dropped = 0;
  for (final profile in profiles) {
    if (profile.id.isEmpty ||
        (profile.host.trim().isEmpty && profile.endpoints.isEmpty)) {
      dropped++;
      continue;
    }
    result.add(connectionFromProfile(profile, updatedAt: now));
  }
  if (dropped > 0) {
    AppLogger.instance.w(
      '[connections] dropped $dropped unaddressable legacy rows',
    );
  }
  return result;
}
