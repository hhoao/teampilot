import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test(
    'capabilitiesOf returns every matching capability in definition order',
    () {
      final first = MarkerCapability('first');
      final second = MarkerCapability('second');
      final registry = CliToolRegistry()
        ..register(FakeCliTool([first, OtherCapability(), second]));

      expect(registry.capabilitiesOf<MarkerCapability>(CliTool.claude), [
        first,
        second,
      ]);
      expect(
        registry.capability<MarkerCapability>(CliTool.claude),
        same(first),
      );
    },
  );

  test('capabilitiesOf returns an empty iterable for an unknown tool', () {
    final registry = CliToolRegistry();

    expect(registry.capabilitiesOf<MarkerCapability>(CliTool.claude), isEmpty);
  });

  test('launchSecurityFor throws when the capability is not registered', () {
    final registry = CliToolRegistry()
      ..register(FakeCliTool([OtherCapability()]));

    expect(
      () => registry.launchSecurityFor(CliTool.claude),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains(CliTool.claude.value),
        ),
      ),
    );
  });

  test('launchesAcpOnly marks only ACP-only CLIs', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);

    expect(registry.launchesAcpOnly(CliTool.gemini), isTrue);
    expect(registry.launchesAcpOnly(CliTool.codebuddy), isTrue);
    for (final cli in [
      CliTool.claude,
      CliTool.codex,
      CliTool.cursor,
      CliTool.opencode,
    ]) {
      expect(registry.launchesAcpOnly(cli), isFalse, reason: cli.value);
    }
    expect(
      registry.launchesAcpOnly(null),
      isFalse,
      reason: 'team sessions never infer ACP from a CLI',
    );
    expect(
      registry.supportsTransport(CliTool.claude, CliTransport.pty),
      isTrue,
    );
    expect(
      registry.supportsTransport(CliTool.claude, CliTransport.acp),
      isTrue,
    );
    expect(
      registry.supportsTransport(CliTool.flashskyai, CliTransport.acp),
      isFalse,
      reason: 'FlashskyAI has no ACP capability',
    );
  });
}

final class FakeCliTool implements CliToolDefinition {
  FakeCliTool(this.capabilities);

  @override
  final List<CliCapability> capabilities;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;
}

final class MarkerCapability implements CliCapability {
  MarkerCapability(this.name);

  final String name;
}

final class OtherCapability implements CliCapability {}
