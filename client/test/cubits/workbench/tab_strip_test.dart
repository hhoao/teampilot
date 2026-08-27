// test/cubits/workbench/tab_strip_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/tab_strip.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';

final _s1 = WorkbenchTabId.session('s1');
final _s2 = WorkbenchTabId.session('s2');
final _s3 = WorkbenchTabId.session('s3');
final _f = WorkbenchTabId.file('/a.dart');
final _d = WorkbenchTabId.diffChanges('/a.dart');

void main() {
  const r = TabStripReducer();
  const empty = TabStrip();

  group('add', () {
    test('appends at end and activates', () {
      final (s, replaced) = r.add(empty, _s1, preview: false);
      expect(s.order, [_s1]);
      expect(s.activeId, _s1);
      expect(replaced, isNull);
    });

    test('replaces an existing preview slot and returns it', () {
      final (s1, _) = r.add(empty, _f, preview: true);
      final (s2, replaced) = r.add(s1, _s1, preview: true);
      expect(replaced, _f);
      expect(s2.order, [_s1]);
      expect(s2.previewIds, {_s1});
    });

    test('pins an existing tab when preview is false', () {
      final (s1, _) = r.add(empty, _s1, preview: true);
      final (s2, _) = r.add(s1, _s1, preview: false);
      expect(s2.previewIds, isEmpty);
      expect(s2.activeId, _s1);
    });
  });

  group('remove', () {
    test('never resurrects the removed id', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      final s3 = r.remove(s2, _s1);
      expect(s3, isNotNull);
      expect(s3!.order, [_s2]);
      expect(s3.order.contains(_s1), isFalse);
    });

    test('activates previous neighbor, else first, else null', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      final (s3, _) = r.add(s2, _s3, preview: false);
      // remove active middle -> previous neighbor
      expect(r.remove(r.activate(s3, _s2), _s2)!.activeId, _s1);
      // remove active first -> new first
      expect(r.remove(r.activate(s3, _s1), _s1)!.activeId, _s2);
      // remove last remaining -> null (landing)
      final (only, _) = r.add(empty, _s1, preview: false);
      expect(r.remove(only, _s1)!.activeId, isNull);
      // absent id -> null (no-op)
      expect(r.remove(s3, _f), isNull);
    });

    test('drops the removed id from previewIds', () {
      final (s1, _) = r.add(empty, _f, preview: true);
      final s2 = r.remove(s1, _f)!;
      expect(s2.previewIds, isEmpty);
    });

    test('clears Landing prefill when removing the final tab', () {
      final (withTab, _) = r.add(empty, _s1, preview: false);
      final withPrefill = r.enterLanding(
        withTab,
        initialText: '审查并继续完成该会话: /data/session',
      );

      final result = r.remove(withPrefill, _s1);

      expect(result, isNotNull);
      expect(result!.order, isEmpty);
      expect(result.landingInitialText, isNull);
    });

    test('clears Landing prefill when removing the final Session tab', () {
      final (withSession, _) = r.add(empty, _s1, preview: false);
      final (withFile, _) = r.add(withSession, _f, preview: false);
      final withPrefill = r.enterLanding(
        withFile,
        initialText: '审查并继续完成该会话: /data/session',
      );

      final result = r.remove(withPrefill, _s1);

      expect(result, isNotNull);
      expect(result!.order, [_f]);
      expect(result.landingInitialText, isNull);
    });

    test(
      'clears Landing prefill when a diff tab remains after Session removal',
      () {
        final (withSession, _) = r.add(empty, _s1, preview: false);
        final (withDiff, _) = r.add(withSession, _d, preview: false);
        final withPrefill = r.enterLanding(
          withDiff,
          initialText: '审查并继续完成该会话: /data/session',
        );

        final result = r.remove(withPrefill, _s1);

        expect(result, isNotNull);
        expect(result!.order, [_d]);
        expect(result.landingInitialText, isNull);
      },
    );

    test(
      'preserves a reference when an unrelated final Session is removed',
      () {
        final (withFile, _) = r.add(empty, _f, preview: false);
        final (withUnrelatedSession, _) = r.add(withFile, _s1, preview: false);
        final withReference = r.enterLanding(
          withUnrelatedSession,
          initialText: '审查并继续完成该会话: /data/referenced',
          referencedSessionId: 'referenced-session',
        );

        final result = r.remove(withReference, _s1);

        expect(result, isNotNull);
        expect(result!.order, [_f]);
        expect(result.landingInitialText, '审查并继续完成该会话: /data/referenced');
        expect(result.landingReferenceSessionId, 'referenced-session');
      },
    );

    test(
      'clears text and provenance together when the reference is removed',
      () {
        final (withSession, _) = r.add(empty, _s1, preview: false);
        final withReference = r.enterLanding(
          withSession,
          initialText: '审查并继续完成该会话: /data/referenced',
          referencedSessionId: 's1',
        );

        final result = r.remove(withReference, _s1)!;

        expect(result.landingInitialText, isNull);
        expect(result.landingReferenceSessionId, isNull);
        expect(
          result.landingInitialTextRevision,
          withReference.landingInitialTextRevision + 1,
        );
      },
    );
  });

  group('reorder / activate / pin / landing', () {
    test('reorder preserves active and preview', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      final s3 = r.reorder(s2, 0, 1);
      expect(s3.order, [_s2, _s1]);
      expect(s3.activeId, _s2);
    });

    test('reorder clamps newIndex == order.length (no crash, order kept)', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      // ReorderableListView may pass newIndex == itemCount when dragging to
      // the end; the reducer must treat it as a no-op, not crash.
      final s3 = r.reorder(s2, 0, s2.order.length);
      expect(identical(s3, s2), isTrue);
      expect(s3.order, [_s1, _s2]);
      expect(s3.activeId, _s2);
    });

    test('activate selects an existing tab', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s2, preview: false);
      expect(r.activate(s2, _s1).activeId, _s1);
      expect(r.activate(s2, _f).activeId, _s2); // absent -> unchanged
    });

    test('pin removes from preview set', () {
      final (s1, _) = r.add(empty, _s1, preview: true);
      final s2 = r.pin(s1, _s1);
      expect(s2.previewIds, isEmpty);
    });

    test('enterLanding clears active but keeps tabs', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final s2 = r.enterLanding(s1);
      expect(s2.activeId, isNull);
      expect(s2.order, [_s1]);
      expect(s2.landingActive, isTrue);
    });

    test('enterLanding stores the initial text while retaining open tabs', () {
      final (withTab, _) = r.add(empty, _s1, preview: false);
      final landing = r.enterLanding(
        withTab,
        initialText: '审查并继续完成该会话: /data/session',
      );

      expect(landing.activeId, isNull);
      expect(landing.order, [_s1]);
      expect(landing.landingInitialText, '审查并继续完成该会话: /data/session');
    });

    test(
      'advances the Landing prefill revision for repeated text requests',
      () {
        const prefill = '审查并继续完成该会话: /data/session';
        final first = r.enterLanding(empty, initialText: prefill);
        final second = r.enterLanding(first, initialText: prefill);

        expect(second.landingInitialText, prefill);
        expect(
          second.landingInitialTextRevision,
          first.landingInitialTextRevision + 1,
        );
      },
    );

    test('non-Landing mutations preserve the Landing prefill', () {
      const prefill = '审查并继续完成该会话: /data/session';
      final landing = TabStrip(
        order: [_s1, _s2],
        previewIds: {_s2},
        landingInitialText: prefill,
      );

      final (added, _) = r.add(landing, _s3, preview: false, activate: false);
      final removed = r.remove(landing, _s1)!;
      final reordered = r.reorder(landing, 0, 1);
      final activated = r.activate(landing, _s1);
      final pinned = r.pin(landing, _s2);

      expect(
        [
          added.landingInitialText,
          removed.landingInitialText,
          reordered.landingInitialText,
          activated.landingInitialText,
          pinned.landingInitialText,
        ],
        [prefill, prefill, prefill, prefill, prefill],
      );
    });
  });

  group('invariants', () {
    test('order has no duplicates after repeated adds', () {
      final (s1, _) = r.add(empty, _s1, preview: false);
      final (s2, _) = r.add(s1, _s1, preview: false);
      expect(s2.order.where((t) => t == _s1).length, 1);
    });
  });
}
