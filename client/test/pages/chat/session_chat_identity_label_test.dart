import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/chat/session_chat_compose_section.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';

void main() {
  AppSession simple(String expertKey) => AppSession(
        sessionId: 's',
        workspaceId: 'w',
        createdAt: 1,
        expertKey: expertKey,
      );

  group('SessionChatComposeSection.resolveIdentityLabel', () {
    test('hides the identity chip for the built-in default expert', () {
      expect(
        SessionChatComposeSection.resolveIdentityLabel(
          session: simple(kBuiltinDefaultExpertKey),
          team: null,
          hubState: null,
          expertFallback: 'None selected',
        ),
        isNull,
      );
    });

    test('hides the identity chip when no expert key is set', () {
      expect(
        SessionChatComposeSection.resolveIdentityLabel(
          session: simple(''),
          team: null,
          hubState: null,
          expertFallback: 'None selected',
        ),
        isNull,
      );
    });

    test('still shows a label for a non-default expert', () {
      final label = SessionChatComposeSection.resolveIdentityLabel(
        session: simple(kBuiltinTeamBuilderExpertKey),
        team: null,
        hubState: null,
        expertFallback: 'None selected',
      );
      expect(label, isNotNull);
      expect(label, isNot('Default'));
    });
  });
}
