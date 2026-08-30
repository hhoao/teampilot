import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/pty_quiet_turn_end.dart';

void main() {
  test('Cursor PTY quiet ends the turn; Claude does not', () {
    expect(ptyQuietEndsTurn(CliTool.cursor), isTrue);
    expect(ptyQuietEndsTurn(CliTool.claude), isFalse);
    expect(ptyQuietEndsTurn(CliTool.codex), isFalse);
  });
}
