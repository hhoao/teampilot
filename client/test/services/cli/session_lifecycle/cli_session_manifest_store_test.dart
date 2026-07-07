import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  late Directory root;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  late CliSessionManifestStore store;

  const workspaceId = 'ws-1';
  const sessionId = 'sess-1';
  const tool = 'cursor';

  setUp(() {
    root = Directory.systemTemp.createTempSync('cli_session_manifest_');
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: root.path, fs: fs);
    store = CliSessionManifestStore(fs: fs, layout: layout);
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  CliSessionManifest sampleManifest({CliSessionPhase phase = CliSessionPhase.persisted}) {
    return CliSessionManifest(
      schemaVersion: 1,
      tool: tool,
      workspaceId: workspaceId,
      sessionId: sessionId,
      workspacePathHash: 'home-hhoa-git-hhoa-teampilot',
      workspaceSlug: 'home-hhoa-git-hhoa-teampilot',
      phase: phase,
      phaseUpdatedAtMs: 1_700_000_000_000,
      shared: const CliSessionManifestShared(
        root: 'runtime/_shared/cursor',
        projectsDir:
            'runtime/_shared/cursor/projects/home-hhoa-git-hhoa-teampilot',
        cliConfigBase: 'runtime/_shared/cursor/cli-config.base.json',
        authDir: 'runtime/_shared/cursor/auth',
      ),
      index: const CliSessionManifestIndex(
        leaderMemberId: 'architect',
        startedAtMs: 1_783_399_900_000,
        finishedAtMs: null,
        lastError: null,
      ),
      members: const {
        'team-lead': CliSessionManifestMember(
          homeRoot: 'runtime/team-lead/cursor/home',
          overlayGeneration: 2,
          chatId: 'f4950284-7dcd-4655-9af3-9a2120ba24d4',
          resumeCapturedAtMs: 1_783_400_100_000,
        ),
      },
    );
  }

  test('round-trip write then read returns equal manifest', () async {
    final manifest = sampleManifest();
    await store.write(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: tool,
      manifest: manifest,
    );

    final readBack = await store.read(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: tool,
    );

    expect(readBack, manifest);
  });

  test('updatePhase mutates phase and phaseUpdatedAtMs', () async {
    final manifest = sampleManifest();
    await store.write(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: tool,
      manifest: manifest,
    );

    const updatedAt = 1_783_400_000_000;
    final updated = await store.updatePhase(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: tool,
      phase: CliSessionPhase.auth,
      phaseUpdatedAtMs: updatedAt,
    );

    expect(updated, isNotNull);
    expect(updated!.phase, CliSessionPhase.auth);
    expect(updated.phaseUpdatedAtMs, updatedAt);

    final readBack = await store.read(
      workspaceId: workspaceId,
      sessionId: sessionId,
      tool: tool,
    );
    expect(readBack!.phase, CliSessionPhase.auth);
    expect(readBack.phaseUpdatedAtMs, updatedAt);
  });
}
