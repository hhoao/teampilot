import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/utils/session/session_chat_identity.dart';

AppSession _session({
  String display = 'old',
  int updatedAt = 1,
  CliTool? cli,
  String presetId = '',
}) => AppSession(
  sessionId: 's1',
  workspaceId: 'ws',
  display: display,
  createdAt: 1,
  updatedAt: updatedAt,
  cli: cli,
  presetId: presetId,
);

void main() {
  test('identity ignores display and updatedAt', () {
    final a = SessionChatIdentity.fromSession(
      _session(display: 'old', updatedAt: 1),
    );
    final b = SessionChatIdentity.fromSession(
      _session(display: 'first user line', updatedAt: 99),
    );
    expect(a, b);
  });

  test('identity changes when preset or cli changes', () {
    final a = SessionChatIdentity.fromSession(_session(presetId: 'p1'));
    final b = SessionChatIdentity.fromSession(
      _session(presetId: 'p2', cli: CliTool.codex),
    );
    expect(a, isNot(b));
  });
}
