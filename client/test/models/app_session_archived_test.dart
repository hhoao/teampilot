import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';

void main() {
  test('archived defaults false and missing JSON is false', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
    );
    expect(s.archived, isFalse);
    final restored = AppSession.fromJson({
      'sessionId': 's1',
      'workspaceId': 'w1',
      'createdAt': 1,
    });
    expect(restored.archived, isFalse);
  });

  test('archived true round-trips in JSON', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      archived: true,
    );
    final json = s.toJson();
    expect(json['archived'], isTrue);
    expect(AppSession.fromJson(json).archived, isTrue);
  });

  test('toJson omits archived when false', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
    );
    expect(s.toJson().containsKey('archived'), isFalse);
  });

  test('copyWith can set and clear archived', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
    );
    expect(s.copyWith(archived: true).archived, isTrue);
    expect(s.copyWith(archived: true).copyWith(archived: false).archived, isFalse);
  });
}
