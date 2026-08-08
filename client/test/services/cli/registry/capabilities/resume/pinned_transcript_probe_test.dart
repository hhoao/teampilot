import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/resume/pinned_transcript_probe.dart';
import '../../../../../support/in_memory_filesystem.dart';

void main() {
  group('probePinnedTranscript bucket scan', () {
    test(
      'prefers a .jsonl transcript file across buckets over a session-dir '
      'in a sibling bucket',
      () async {
        final fs = InMemoryFilesystem();
        const root = '/layout';
        const sid = 'task-1';

        // The "-client" bucket holds a session directory (workflows sidecar,
        // no transcript) and sorts BEFORE the bucket that holds the real
        // ".jsonl". Regression: scanning returned the first match in
        // listDir order, so the dir match shadowed the real file and the
        // Claude locator (requires isFile) then returned null → empty chat.
        await fs.ensureDir(
          p.join(root, 'projects', '-client', sid, 'workflows'),
        );
        await fs.writeString(
          p.join(root, 'projects', '-card', '$sid.jsonl'),
          '{"type":"assistant","message":{"id":"a1","content":"hi"}}\n',
        );

        final result = await probePinnedTranscript(
          fs: fs,
          toolRoots: [root],
          sessionId: sid,
          bucket: '',
          layoutSegments: const ['projects'],
        );

        expect(result.exists, isTrue);
        expect(result.matchedPath, p.join(root, 'projects', '-card', '$sid.jsonl'));
      },
    );

    test('falls back to session-dir match when no .jsonl exists anywhere', () async {
      final fs = InMemoryFilesystem();
      const root = '/layout';
      const sid = 'task-2';

      await fs.ensureDir(p.join(root, 'projects', '-client', sid, 'workflows'));
      await fs.ensureDir(p.join(root, 'projects', '-card', sid));

      final result = await probePinnedTranscript(
        fs: fs,
        toolRoots: [root],
        sessionId: sid,
        bucket: '',
        layoutSegments: const ['projects'],
      );

      expect(result.exists, isTrue);
      expect(result.matchedPath, endsWith(p.join(sid)));
    });

    test('respects the pinned bucket dir first when it has the file', () async {
      final fs = InMemoryFilesystem();
      const root = '/layout';
      const sid = 'task-3';

      await fs.ensureDir(p.join(root, 'projects', '-client', sid, 'workflows'));
      await fs.writeString(
        p.join(root, 'projects', 'main-bucket', '$sid.jsonl'),
        '{"type":"user","message":{"id":"u1","content":"x"}}\n',
      );

      final result = await probePinnedTranscript(
        fs: fs,
        toolRoots: [root],
        sessionId: sid,
        bucket: 'main-bucket',
        layoutSegments: const ['projects'],
      );

      expect(result.exists, isTrue);
      expect(result.matchedPath, p.join(root, 'projects', 'main-bucket', '$sid.jsonl'));
    });

    test(
      'matchDirectories:false ignores a session-dir-only bucket (transcript '
      'location semantics)',
      () async {
        final fs = InMemoryFilesystem();
        const root = '/layout';
        const sid = 'task-4';

        // Only a workflow sidecar directory exists — no `.jsonl` anywhere.
        await fs.ensureDir(p.join(root, 'projects', '-client', sid, 'workflows'));

        final result = await probePinnedTranscript(
          fs: fs,
          toolRoots: [root],
          sessionId: sid,
          bucket: '',
          layoutSegments: const ['projects'],
          matchDirectories: false,
        );

        // A sidecar dir must never satisfy transcript location.
        expect(result.exists, isFalse);
        expect(result.matchedPath, isNull);
      },
    );

    test(
      'matchDirectories:false still finds the .jsonl file when both a '
      'sidecar dir and the real file exist',
      () async {
        final fs = InMemoryFilesystem();
        const root = '/layout';
        const sid = 'task-5';

        await fs.ensureDir(p.join(root, 'projects', '-client', sid, 'workflows'));
        await fs.writeString(
          p.join(root, 'projects', '-card', '$sid.jsonl'),
          '{"type":"assistant","message":{"id":"a1","content":"hi"}}\n',
        );

        final result = await probePinnedTranscript(
          fs: fs,
          toolRoots: [root],
          sessionId: sid,
          bucket: '',
          layoutSegments: const ['projects'],
          matchDirectories: false,
        );

        expect(result.exists, isTrue);
        expect(result.matchedPath, p.join(root, 'projects', '-card', '$sid.jsonl'));
      },
    );

    test(
      'matchDirectories:false skips the pinned-bucket directory match too',
      () async {
        final fs = InMemoryFilesystem();
        const root = '/layout';
        const sid = 'task-6';

        // The pinned bucket has only a session dir (no file); a sibling
        // bucket has the real transcript.
        await fs.ensureDir(p.join(root, 'projects', 'main-bucket', sid));
        await fs.writeString(
          p.join(root, 'projects', '-card', '$sid.jsonl'),
          '{"type":"assistant","message":{"id":"a1","content":"hi"}}\n',
        );

        final result = await probePinnedTranscript(
          fs: fs,
          toolRoots: [root],
          sessionId: sid,
          bucket: 'main-bucket',
          layoutSegments: const ['projects'],
          matchDirectories: false,
        );

        expect(result.exists, isTrue);
        expect(result.matchedPath, p.join(root, 'projects', '-card', '$sid.jsonl'));
      },
    );
  });
}
