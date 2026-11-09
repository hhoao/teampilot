import 'dart:convert';

import '../../models/remote_target.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/remote_target_repository.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'storage_failure.dart';

class RemoteTargetMigrationResult {
  const RemoteTargetMigrationResult({
    required this.migrated,
    required this.skipped,
  });

  final int migrated;
  final bool skipped;
}

Future<RemoteTargetMigrationResult> migrateSshProfiles({
  required String nativeAppDataPath,
  required Filesystem localFs,
  required RemoteTargetRepository targetRepo,
}) async {
  final marker = localFs.pathContext.join(
    nativeAppDataPath,
    '.remote-targets-migrated.v1',
  );
  if ((await localFs.stat(marker)).exists) {
    return const RemoteTargetMigrationResult(migrated: 0, skipped: true);
  }

  final legacyFile = localFs.pathContext.join(
    nativeAppDataPath,
    'ssh_profiles',
    'profiles.json',
  );
  final legacy = <SshProfile>[];
  if ((await localFs.stat(legacyFile)).isFile) {
    try {
      final raw = await localFs.readString(legacyFile);
      final json = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      if (json is List) {
        legacy.addAll(
          json.whereType<Map<String, Object?>>().map(SshProfile.fromJson),
        );
      }
    } on FormatException catch (error) {
      // Transport detection is partly message-based, so a closed channel can
      // surface as a parse-typed error. It must never be swallowed here.
      if (isStorageTransportFailure(error)) rethrow;
      return _unreadableLegacy(legacyFile);
    } on TypeError catch (error) {
      // Malformed JSON shapes fail casts in SshProfile.fromJson as TypeError.
      if (isStorageTransportFailure(error)) rethrow;
      return _unreadableLegacy(legacyFile);
    }
  }

  final current = await targetRepo.loadAll();
  final existing = {for (final t in current) t.id};
  final migrated = <RemoteTarget>[
    for (final profile in legacy)
      if (!existing.contains(profile.id)) _toTarget(profile),
  ];
  if (migrated.isNotEmpty) {
    await targetRepo.saveAll([...current, ...migrated]);
  }
  await localFs.atomicWrite(marker, '1');
  // On a local home plane the legacy device-local `profiles.json` shares this
  // path with SshServerProfileRepository's catalog. A leftover would be parsed
  // as ghost "server profiles" (full SshProfile schema) and a later save would
  // rewrite it in the reduced schema, dropping vaultEntryId/endpoints/etc. and
  // skipping the first-connect seed. Relocate it (recoverable), best-effort: a
  // failed rename must never abort migration or skip the marker just written.
  if ((await localFs.stat(legacyFile)).isFile) {
    try {
      await localFs.rename(legacyFile, '$legacyFile.legacy.v1');
    } on Object {
      // Content-free: never the caught error and never the file bytes.
      AppLogger.instance.w(
        '[remote-targets] failed to relocate legacy profiles at $legacyFile',
      );
    }
  }
  return RemoteTargetMigrationResult(migrated: migrated.length, skipped: false);
}

RemoteTarget _toTarget(SshProfile profile) => RemoteTarget(
  id: profile.id,
  name: profile.name,
  host: profile.host,
  port: profile.port,
  username: profile.username,
  authType: profile.authType,
  vaultEntryId: profile.vaultEntryId,
  endpoints: profile.endpoints,
  hostKeyFingerprints: profile.hostKeyFingerprints,
  lastGoodKind: profile.lastGoodKind,
  lastHome: profile.lastHome,
  lastAppDataRoot: profile.lastAppDataRoot,
  embeddedTarget: profile.embeddedTarget,
  relayUrl: profile.relayUrl,
  pairedDesktopId: profile.pairedDesktopId,
  updatedAt: profile.updatedAt,
);

RemoteTargetMigrationResult _unreadableLegacy(String legacyFile) {
  // Content-free diagnostic: FormatException.message embeds a source excerpt
  // that can carry host/username/vaultEntryId, so log the path only — never
  // the caught error or the file bytes.
  AppLogger.instance.w(
    '[remote-targets] unreadable legacy profiles at $legacyFile; '
    'keeping file for retry',
  );
  // 解析失败：保留原文件，不写标记，下次启动重试。
  return const RemoteTargetMigrationResult(migrated: 0, skipped: false);
}
