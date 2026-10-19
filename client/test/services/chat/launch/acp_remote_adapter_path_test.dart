import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/connect/acp_runtime_attach.dart';

void main() {
  test('remote resolver returns the injected absolute adapter path', () {
    final resolver = acpAdapterPathResolverFor(
      remote: true,
      remoteAdapterPath: '/home/u/.local/bin/claude-agent-acp',
      localResolver: (tool) => '/local/${tool.value}',
    );
    expect(resolver(CliTool.claude), '/home/u/.local/bin/claude-agent-acp');
  });

  test('remote resolver returns null when no override was found', () {
    final resolver = acpAdapterPathResolverFor(
      remote: true,
      remoteAdapterPath: null,
      localResolver: (tool) => '/local/${tool.value}',
    );
    expect(resolver(CliTool.claude), isNull);
  });

  test('local resolver returns the boot-discovered adapter path', () {
    final resolver = acpAdapterPathResolverFor(
      remote: false,
      remoteAdapterPath: '/ignored',
      localResolver: (tool) => '/local/${tool.value}',
    );
    expect(resolver(CliTool.claude), '/local/claude');
  });
}
