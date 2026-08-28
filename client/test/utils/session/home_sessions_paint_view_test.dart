import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/utils/session/home_sessions_paint_view.dart';

AppSession _session({
  String sessionId = 's1',
  String workspaceId = 'ws',
  String display = 'title',
  int createdAt = 1,
  int updatedAt = 2,
  CliTool? cli,
  String provider = '',
}) => AppSession(
  sessionId: sessionId,
  workspaceId: workspaceId,
  display: display,
  createdAt: createdAt,
  updatedAt: updatedAt,
  cli: cli,
  provider: provider,
);

void main() {
  test('paint view ignores CLI and provider changes', () {
    final a = HomeSessionsPaintView([_session(cli: CliTool.claude)]);
    final b = HomeSessionsPaintView([
      _session(cli: CliTool.codex, provider: 'openai'),
    ]);
    expect(a, b);
  });

  test('paint view changes when display or timestamps change', () {
    final a = HomeSessionsPaintView([_session(display: 'old', updatedAt: 1)]);
    final b = HomeSessionsPaintView([
      _session(display: 'first user line', updatedAt: 99),
    ]);
    expect(a, isNot(b));
  });

  test('paint view changes when a session is added', () {
    final a = HomeSessionsPaintView([_session()]);
    final b = HomeSessionsPaintView([_session(), _session(sessionId: 's2')]);
    expect(a, isNot(b));
  });
}
