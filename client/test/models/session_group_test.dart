import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_group.dart';

void main() {
  group('SessionGroup', () {
    test('json round-trip preserves fields', () {
      const group = SessionGroup(
        id: 'g1',
        name: '待办',
        sessionIds: ['s1', 's2'],
        collapsed: true,
      );
      final decoded = SessionGroup.fromJson(
        Map<String, Object?>.from(group.toJson()),
      );
      expect(decoded, group);
    });

    test('fromJson tolerates junk and dedupes session ids', () {
      final decoded = SessionGroup.fromJson(const {
        'id': ' g2 ',
        'name': 42,
        'sessionIds': ['a', 'a', 'b', 7],
        'collapsed': 'yes',
      });
      expect(decoded.id, 'g2');
      expect(decoded.name, '');
      expect(decoded.sessionIds, ['a', 'b']);
      expect(decoded.collapsed, isFalse);
    });

    test('copyWith replaces only given fields', () {
      const group = SessionGroup(id: 'g1', name: 'A', sessionIds: ['s1']);
      final renamed = group.copyWith(name: 'B');
      expect(renamed.name, 'B');
      expect(renamed.id, 'g1');
      expect(renamed.sessionIds, ['s1']);
      expect(renamed.collapsed, isFalse);
    });
  });

  group('SessionGroupsFile', () {
    test('round-trip keeps group order and default version', () {
      const file = SessionGroupsFile(groups: [
        SessionGroup(id: 'g1', name: 'A'),
        SessionGroup(id: 'g2', name: 'B', collapsed: true),
      ]);
      final decoded = SessionGroupsFile.fromJson(
        Map<String, Object?>.from(file.toJson()),
      );
      expect(decoded.version, SessionGroupsFile.currentVersion);
      expect(decoded.groups, file.groups);
    });

    test('fromJson on empty map yields empty groups', () {
      expect(SessionGroupsFile.fromJson(const {}).groups, isEmpty);
    });
  });
}
