import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_policy.dart';

void main() {
  test('claudeAllowEntries lists ssh tools', () {
    expect(
      SessionSshMcpPolicy.claudeAllowEntries,
      containsAll([
        'mcp__ssh__list-servers',
        'mcp__ssh__execute-command',
        'mcp__ssh__upload',
        'mcp__ssh__download',
      ]),
    );
  });

  test('cursorAllowEntries lists ssh tools', () {
    expect(
      SessionSshMcpPolicy.cursorAllowEntries,
      containsAll([
        'Mcp(ssh:list-servers)',
        'Mcp(ssh:execute-command)',
        'Mcp(ssh:upload)',
        'Mcp(ssh:download)',
      ]),
    );
  });
}
