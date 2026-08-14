import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/claude/capabilities/executable.dart';
import 'package:teampilot/services/cli/codex/capabilities/executable.dart';
import 'package:teampilot/services/cli/cursor/capabilities/executable.dart';
import 'package:teampilot/services/cli/opencode/capabilities/executable.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/team_behavior_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/noop_cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

class _EchoCapability implements CliCapability {
  const _EchoCapability(this.value);
  final String value;
}

class _FakeTeamBehavior implements TeamBehaviorCapability {
  const _FakeTeamBehavior({this.supportsNativeTeam = false});
  @override
  final bool supportsNativeTeam;
  @override
  bool get longBlockingWaitForMessage => false;
  @override
  bool get supportsLocalStdioBridge => false;
  @override
  Set<String> get doneEventNames => const {};
  @override
  bool get requiresPtyFallback => false;
  @override
  bool get usesDoorbellPush => false;
  @override
  bool get defaultForceWaitBeforeStop => false;
  @override
  bool get usesClaudeRoster => false;
  @override
  bool get usesShellActivity => false;
  @override
  MemberAgentPresetStyle? get agentPresetStyle => null;
}

class _FakeTool implements CliToolDefinition {
  const _FakeTool(this.id, this.isLaunchSupported, this.capabilities);
  @override
  final CliTool id;
  @override
  final bool isLaunchSupported;
  @override
  final Iterable<CliCapability> capabilities;
}

void main() {
  test('capability returns registered implementation', () {
    final registry = CliToolRegistry();
    registry.register(
      const _FakeTool(CliTool.flashskyai, true, [_EchoCapability('ok')]),
    );
    expect(
      registry.capability<_EchoCapability>(CliTool.flashskyai)?.value,
      'ok',
    );
    expect(registry.capability<_EchoCapability>(CliTool.claude), isNull);
  });

  test('launchable filters isLaunchSupported', () {
    final registry = CliToolRegistry();
    registry.register(const _FakeTool(CliTool.claude, true, []));
    registry.register(const _FakeTool(CliTool.codex, false, []));
    expect(registry.launchable.map((d) => d.id), [CliTool.claude]);
  });

  test('nativeTeamLaunchable requires TeamBehaviorCapability', () {
    final registry = CliToolRegistry();
    registry.register(
      const _FakeTool(
        CliTool.claude,
        true,
        [_FakeTeamBehavior(supportsNativeTeam: true)],
      ),
    );
    registry.register(const _FakeTool(CliTool.codex, true, []));
    registry.register(
      const _FakeTool(
        CliTool.flashskyai,
        true,
        [_FakeTeamBehavior(supportsNativeTeam: true)],
      ),
    );
    expect(registry.nativeTeamLaunchable.map((d) => d.id), [
      CliTool.claude,
      CliTool.flashskyai,
    ]);
    expect(registry.supportsNativeTeam(CliTool.codex), isFalse);
    expect(registry.supportsNativeTeam(CliTool.claude), isTrue);
  });

  test('built-in member agent preset CLIs are claude and flashskyai only', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    expect(registry.supportsMemberAgentPreset(CliTool.codex), isFalse);
    expect(
      registry
          .all
          .where((d) => registry.memberAgentPresetStyle(d.id) != null)
          .map((d) => d.id)
          .toSet(),
      {CliTool.claude, CliTool.flashskyai},
    );
    expect(
      registry.memberAgentPresetStyle(CliTool.claude),
      MemberAgentPresetStyle.claudeAgentType,
    );
    expect(
      registry.memberAgentPresetStyle(CliTool.flashskyai),
      MemberAgentPresetStyle.flashskyaiCatalog,
    );
  });

  test('built-in native team CLIs are claude and flashskyai only', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    expect(registry.nativeTeamLaunchable.map((d) => d.id).toSet(), {
      CliTool.claude,
      CliTool.flashskyai,
    });
    expect(registry.supportsNativeTeam(CliTool.codex), isFalse);

    expect(
      CliToolRegistry.builtIn().nativeTeamLaunchable.map((d) => d.id).toSet(),
      {CliTool.claude, CliTool.flashskyai},
    );
  });

  test('built-in registry covers every CliTool value', () {
    final registry = CliToolRegistry.builtIn();
    expect(registry.all.length, CliTool.values.length);
    for (final cli in CliTool.values) {
      expect(registry.tryGet(cli), isNotNull, reason: cli.value);
    }
  });

  test('built-in launchable tools have CliSessionCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final def in registry.launchable) {
      expect(registry.capability<CliSessionCapability>(def.id), isNotNull);
    }
  });

  test('claude built-in has CliExecutableCapability with install support', () {
    final registry = CliToolRegistry.builtIn();
    final executable = registry.capability<CliExecutableCapability>(
      CliTool.claude,
    );
    expect(executable, isA<ClaudeExecutableCapability>());
    expect(executable!.supportsInstaller, isTrue);
  });

  test('codex built-in has npm executable with install support', () {
    final registry = CliToolRegistry.builtIn();
    final executable = registry.capability<CliExecutableCapability>(
      CliTool.codex,
    );
    expect(executable, isA<CodexExecutableCapability>());
    expect(executable!.supportsInstaller, isTrue);
  });

  test('opencode built-in has npm executable with install support', () {
    final registry = CliToolRegistry.builtIn();
    final executable = registry.capability<CliExecutableCapability>(
      CliTool.opencode,
    );
    expect(executable, isA<OpencodeExecutableCapability>());
    expect(executable!.supportsInstaller, isTrue);
  });

  test('cursor built-in has curl executable with install support', () {
    final registry = CliToolRegistry.builtIn();
    final executable = registry.capability<CliExecutableCapability>(
      CliTool.cursor,
    );
    expect(executable, isA<CursorExecutableCapability>());
    expect(executable!.supportsInstaller, isTrue);
  });

  test('built-in launchable tools have ConfigProfileCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final def in registry.launchable) {
      expect(registry.capability<ConfigProfileCapability>(def.id), isNotNull);
    }
  });

  test('opencode has a ProviderCatalogCapability', () {
    final registry = CliToolRegistry.builtIn();
    expect(
      registry.capability<ProviderCapability>(CliTool.opencode),
      isNotNull,
    );
  });

  test('built-in launchable tools have ProviderModelCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final def in registry.launchable) {
      expect(registry.capability<ProviderCapability>(def.id), isNotNull);
    }
  });

  test('lifecycleFor returns no-op when tool registers no session capability', () {
    final registry = CliToolRegistry();
    registry.register(const _FakeTool(CliTool.codex, true, []));
    expect(
      registry.lifecycleFor(CliTool.codex),
      isA<NoopCliSessionCapability>(),
    );
  });

  test('lifecycleFor returns registered session capability', () {
    const lifecycle = NoopCliSessionCapability();
    final registry = CliToolRegistry();
    registry.register(
      const _FakeTool(CliTool.codex, true, [lifecycle]),
    );
    expect(identical(registry.lifecycleFor(CliTool.codex), lifecycle), isTrue);
  });
}
