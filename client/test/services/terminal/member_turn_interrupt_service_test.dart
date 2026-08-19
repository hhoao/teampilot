import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/team/terminal_activity_tracker.dart';
import 'package:teampilot/services/terminal/member_turn_interrupt_service.dart';
import 'package:teampilot/services/terminal/terminal_launch_controller.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import '../../support/rust_lib_test_init.dart';

class _FakeShell extends TerminalSession {
  _FakeShell({required this.connected})
    : super(
        executable: 'unused',
        validateLaunch: false,
        parseExecutable: false,
        launchController: TerminalLaunchController(
          engine: TerminalEngine(config: TerminalConfig.defaults()),
          activityTracker: TerminalActivityTracker(),
          defaultExecutable: 'unused',
          startupDeadline: const Duration(seconds: 5),
          confirmFallback: const Duration(milliseconds: 50),
          validateLaunch: false,
        ),
      );

  final bool connected;

  @override
  bool get isConnected => connected;
}

void main() {
  setUpAll(initRustLibForTests);
  test('writes Ctrl+C and aborts inject first', () async {
    final aborted = <String>[];
    final writes = <String>[];
    final service = MemberTurnInterruptService(
      cliToolRegistry: CliToolRegistry.builtIn(),
      abortMemberInject: (s, m) => aborted.add('$s:$m'),
      writePty: (_, text) => writes.add(text),
    );
    await service.interrupt(
      sessionId: 's1',
      memberId: 'm1',
      shell: _FakeShell(connected: true),
      cli: CliTool.claude,
    );
    expect(aborted, ['s1:m1']);
    expect(writes, ['\x03']);
  });

  test('no-op when shell disconnected', () async {
    final aborted = <String>[];
    final writes = <String>[];
    final service = MemberTurnInterruptService(
      cliToolRegistry: CliToolRegistry.builtIn(),
      abortMemberInject: (s, m) => aborted.add('$s:$m'),
      writePty: (_, text) => writes.add(text),
    );
    await service.interrupt(
      sessionId: 's1',
      memberId: 'm1',
      shell: _FakeShell(connected: false),
      cli: CliTool.claude,
    );
    expect(aborted, isEmpty);
    expect(writes, isEmpty);
  });
}
