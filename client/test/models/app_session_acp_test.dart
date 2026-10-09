import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('claude simple defaults acp false', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
    );
    expect(s.acp, isFalse);
    expect(s.toJson().containsKey('acp'), isFalse);
  });

  test('gemini simple infers acp true when omitted', () {
    final s = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.gemini,
    );
    expect(s.acp, isTrue);
    expect(s.toJson()['acp'], isTrue);
  });

  test('legacy JSON without acp: gemini simple is true, claude is false', () {
    expect(
      AppSession.fromJson({
        'sessionId': 's1',
        'workspaceId': 'w1',
        'createdAt': 1,
        'cli': 'gemini',
      }).acp,
      isTrue,
    );
    expect(
      AppSession.fromJson({
        'sessionId': 's1',
        'workspaceId': 'w1',
        'createdAt': 1,
        'cli': 'claude',
      }).acp,
      isFalse,
    );
  });

  test('acp true round-trips; explicit false wins over gemini inference', () {
    final on = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
      acp: true,
    );
    expect(AppSession.fromJson(on.toJson()).acp, isTrue);

    final geminiOff = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.gemini,
      acp: false,
    );
    expect(geminiOff.acp, isFalse);
  });
}
