import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';

void main() {
  group('SessionPurpose', () {
    test('unknown and missing session purpose fail closed to normal', () {
      final base = {'sessionId': 's', 'workspaceId': 'w', 'createdAt': 1};
      expect(AppSession.fromJson(base).purpose, SessionPurpose.normal);
      expect(
        AppSession.fromJson({...base, 'purpose': 'future-admin'}).purpose,
        SessionPurpose.normal,
      );
    });

    test('team generation purpose and workflow survive JSON round trip', () {
      final session = AppSession(
        sessionId: 'builder',
        workspaceId: 'workspace',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'workflow',
        createdAt: 1,
      );
      expect(AppSession.fromJson(session.toJson()), session);
    });

    test('workflowId normalizes to empty for normal purpose', () {
      final session = AppSession(
        sessionId: 'builder',
        workspaceId: 'workspace',
        workflowId: 'workflow',
        createdAt: 1,
      );
      expect(session.purpose, SessionPurpose.normal);
      expect(session.workflowId, isEmpty);
      expect(session.toJson().containsKey('workflowId'), isFalse);
      expect(session.toJson().containsKey('purpose'), isFalse);
    });

    test('invalid workflow id characters are rejected', () {
      expect(isValidTeamGenerationWorkflowId('wf-123'), isTrue);
      expect(isValidTeamGenerationWorkflowId('A_b.1'), isFalse);
      expect(isValidTeamGenerationWorkflowId('../escape'), isFalse);
      expect(isValidTeamGenerationWorkflowId('with space'), isFalse);
      expect(isValidTeamGenerationWorkflowId('-leading'), isFalse);
      expect(isValidTeamGenerationWorkflowId(''), isFalse);
      expect(
        isValidTeamGenerationWorkflowId('a' * 129),
        isFalse,
      );
      expect(isValidTeamGenerationWorkflowId('a' * 128), isTrue);
    });

    test('equality includes purpose and workflow', () {
      final a = AppSession(
        sessionId: 's',
        workspaceId: 'w',
        purpose: SessionPurpose.teamGeneration,
        workflowId: 'wf',
        createdAt: 1,
      );
      final b = a.copyWith();
      expect(a, b);
      final c = a.copyWith(purpose: SessionPurpose.normal);
      expect(a, isNot(c));
    });
  });
}
