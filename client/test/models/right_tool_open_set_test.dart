import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/right_tool_open_set.dart';

void main() {
  group('RightToolOpenSet', () {
    test('sanitizeIds drops unknown, blanks, and duplicates, keeps order', () {
      expect(
        RightToolOpenSet.sanitizeIds(const [
          'members',
          'nope',
          'members',
          'fileTree',
          1,
          '',
        ]),
        ['members', 'fileTree'],
      );
      expect(RightToolOpenSet.sanitizeIds(null), isEmpty);
      expect(RightToolOpenSet.sanitizeIds('members'), isEmpty);
    });

    test('sanitize drops dismissed ids that are also open', () {
      final set = RightToolOpenSet.sanitize(
        openIds: const ['members', 'mailbox'],
        selectedId: 'bogus',
        dismissedIds: const ['mailbox', 'board', 'nope'],
      );
      expect(set.openIds, ['members', 'mailbox']);
      expect(set.selectedId, isNull);
      expect(set.dismissedIds, ['board']);
    });

    test('visible intersection keeps hidden ids in memory', () {
      const set = RightToolOpenSet(
        openIds: ['members', 'fileTree', 'mailbox'],
        selectedId: 'members',
      );
      expect(set.visibleOpenIds(const ['fileTree', 'git']), ['fileTree']);
      expect(set.visibleSelectedId(const ['fileTree', 'git']), 'fileTree');
      expect(set.openIds, ['members', 'fileTree', 'mailbox']);
      expect(set.selectedId, 'members');
    });

    test('opened adds, selects, and clears dismissed', () {
      const set = RightToolOpenSet(
        openIds: ['fileTree'],
        selectedId: 'fileTree',
        dismissedIds: ['mailbox', 'board'],
      );
      final next = set.opened('mailbox');
      expect(next.openIds, ['fileTree', 'mailbox']);
      expect(next.selectedId, 'mailbox');
      expect(next.dismissedIds, ['board']);
    });

    test('closed records dismissed and reselects a visible neighbor', () {
      const set = RightToolOpenSet(
        openIds: ['members', 'fileTree', 'mailbox'],
        selectedId: 'fileTree',
      );
      final next = set.closed(
        'fileTree',
        catalog: const ['members', 'fileTree', 'mailbox'],
      );
      expect(next.openIds, ['members', 'mailbox']);
      expect(next.dismissedIds, ['fileTree']);
      expect(next.selectedId, 'members');
    });

    test('closed keeps unavailable ids and can clear visible selection', () {
      const set = RightToolOpenSet(
        openIds: ['members', 'fileTree'],
        selectedId: 'fileTree',
      );
      final next = set.closed('fileTree', catalog: const ['fileTree']);
      expect(next.openIds, ['members']);
      expect(next.dismissedIds, ['fileTree']);
      expect(next.selectedId, isNull);
      expect(next.visibleOpenIds(const ['fileTree']), isEmpty);
    });

    test('selected opens if needed', () {
      const set = RightToolOpenSet(
        openIds: ['fileTree'],
        selectedId: 'fileTree',
      );
      final next = set.selected('git');
      expect(next.openIds, ['fileTree', 'git']);
      expect(next.selectedId, 'git');
    });

    test(
      'team seed appends members and mailbox when available and not dismissed',
      () {
        const set = RightToolOpenSet(
          openIds: ['fileTree'],
          selectedId: 'fileTree',
        );
        final next = set.seededForTeam(const [
          'fileTree',
          'members',
          'mailbox',
          'board',
        ]);
        expect(next.openIds, ['fileTree', 'members', 'mailbox']);
        expect(next.selectedId, 'fileTree');
        expect(next.dismissedIds, isEmpty);
      },
    );

    test('team seed skips mailbox when it is not in the catalog', () {
      const set = RightToolOpenSet();
      final next = set.seededForTeam(const ['members', 'fileTree']);
      expect(next.openIds, ['members']);
      expect(next.selectedId, 'members');
    });

    test('team seed does not revive dismissed mailbox', () {
      const set = RightToolOpenSet(
        openIds: ['members'],
        selectedId: 'members',
        dismissedIds: ['mailbox'],
      );
      final next = set.seededForTeam(const ['members', 'mailbox']);
      expect(next.openIds, ['members']);
      expect(next.dismissedIds, ['mailbox']);
    });

    test('empty open set still seeds team tools', () {
      const set = RightToolOpenSet();
      final next = set.seededForTeam(const ['members', 'mailbox', 'board']);
      expect(next.openIds, ['members', 'mailbox']);
      expect(next.selectedId, 'members');
    });

    test('native then mixed seeds mailbox once it is available', () {
      final native = const RightToolOpenSet().seededForTeam(const ['members']);
      expect(native.openIds, ['members']);
      final mixed = native.seededForTeam(const ['members', 'mailbox']);
      expect(mixed.openIds, ['members', 'mailbox']);
    });

    test('team seed does not add board', () {
      final next = const RightToolOpenSet().seededForTeam(const [
        'members',
        'mailbox',
        'board',
      ]);
      expect(next.openIds, isNot(contains('board')));
    });

    test('seed is a no-op when there is nothing to add', () {
      const set = RightToolOpenSet(
        openIds: ['members', 'mailbox'],
        selectedId: 'mailbox',
      );
      expect(set.seededForTeam(const ['members', 'mailbox']), same(set));
    });
  });
}
