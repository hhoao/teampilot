import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_index_completion_probe.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/session_lifecycle/cursor/cursor_session_lifecycle_paths.dart';
import 'package:teampilot/services/cli/session_lifecycle/cli_session_manifest_store.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  group('CursorIndexCompletionProbe.scan', () {
    test('returns done when log tail contains Indexing finished', () {
      const tail = '''
2026-07-07T10:00:01Z Starting index
2026-07-07T10:05:00Z Indexing finished
''';

      expect(CursorIndexCompletionProbe.scan(tail), IndexProbeResult.done);
    });

    test('returns failed when log tail contains Indexing run failed', () {
      const tail = '''
2026-07-07T10:00:01Z Starting index
2026-07-07T10:05:00Z Indexing run failed: socket hang up
''';

      expect(CursorIndexCompletionProbe.scan(tail), IndexProbeResult.failed);
    });

    test('returns pending when no completion markers are present', () {
      const tail = '''
2026-07-07T10:00:01Z Starting index
2026-07-07T10:00:02Z walking tree
''';

      expect(CursorIndexCompletionProbe.scan(tail), IndexProbeResult.pending);
    });

    test('prefers failed when both markers appear in tail', () {
      const tail = '''
Indexing finished
Indexing run failed
''';

      expect(CursorIndexCompletionProbe.scan(tail), IndexProbeResult.failed);
    });
  });

  group('CursorSessionLifecycleCapability index transitions', () {
    Future<CliSessionManifestStore> seededIndexingStore() async {
      final fs = InMemoryFilesystem();
      final layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
      final store = CliSessionManifestStore(fs: fs, layout: layout);
      await store.write(
        workspaceId: 'ws',
        sessionId: 'sess',
        tool: CursorSessionLifecyclePaths.tool,
        manifest: CliSessionManifest(
          tool: CursorSessionLifecyclePaths.tool,
          workspaceId: 'ws',
          sessionId: 'sess',
          workspacePathHash: 'slug',
          workspaceSlug: 'slug',
          phase: CliSessionPhase.indexing,
          shared: const CliSessionManifestShared(
            root: 'runtime/_shared/cursor',
            projectsDir: 'runtime/_shared/cursor/projects/slug',
            cliConfigBase: 'runtime/_shared/cursor/cli-config.base.json',
            authDir: 'runtime/_shared/cursor/auth',
          ),
          index: const CliSessionManifestIndex(leaderMemberId: 'team-lead'),
        ),
      );
      return store;
    }

    test('markIndexDone moves manifest to ready with finishedAtMs', () async {
      final store = await seededIndexingStore();
      final capability = CursorSessionLifecycleCapability(
        manifestStore: store,
        clock: () => 1_700_000_000_000,
      );

      await capability.markIndexDone(workspaceId: 'ws', sessionId: 'sess');

      final manifest = await store.read(
        workspaceId: 'ws',
        sessionId: 'sess',
        tool: CursorSessionLifecyclePaths.tool,
      );
      expect(manifest!.phase, CliSessionPhase.ready);
      expect(manifest.index.finishedAtMs, 1_700_000_000_000);
    });

    test('markIndexFailed moves manifest to degraded with lastError', () async {
      final store = await seededIndexingStore();
      final capability = CursorSessionLifecycleCapability(manifestStore: store);

      await capability.markIndexFailed(
        workspaceId: 'ws',
        sessionId: 'sess',
        error: 'socket hang up',
      );

      final manifest = await store.read(
        workspaceId: 'ws',
        sessionId: 'sess',
        tool: CursorSessionLifecyclePaths.tool,
      );
      expect(manifest!.phase, CliSessionPhase.degraded);
      expect(manifest.index.lastError, 'socket hang up');
    });
  });
}
