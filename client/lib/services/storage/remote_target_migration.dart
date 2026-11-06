import 'dart:convert';

import '../../models/remote_target.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/remote_target_repository.dart';
import '../io/filesystem.dart';

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
    } on Object {
      // 解析失败：保留原文件，不写标记，下次启动重试。
      return const RemoteTargetMigrationResult(migrated: 0, skipped: false);
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
  return RemoteTargetMigrationResult(
    migrated: migrated.length,
    skipped: false,
  );
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
