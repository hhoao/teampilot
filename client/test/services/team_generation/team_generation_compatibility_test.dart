import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/mcp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/team_behavior_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/team_generation/team_generation_compatibility.dart';

CliPreset preset(String id, CliTool cli) => CliPreset(
  id: id,
  name: id,
  cli: cli,
  provider: 'official',
  model: 'model',
  createdAt: 0,
  updatedAt: 0,
);

EffectiveGenerateModelPoolEntry poolEntry(String id, CliTool cli) =>
    EffectiveGenerateModelPoolEntry(
      rank: 1,
      source: GenerateModelPoolEntry(
        id: id,
        cli: cli,
        provider: 'official',
        model: 'model',
      ),
      preset: preset(id, cli),
    );

/// Configurable fake definition so tests compose capabilities explicitly.
class _FakeDefinition implements CliToolDefinition {
  _FakeDefinition(this.id, {this.caps = const <CliCapability>[]});

  @override
  final CliTool id;

  final List<CliCapability> caps;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => caps;
}

class _SessionCap implements CliSessionCapability {
  const _SessionCap();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _SkillCap implements SkillCapability {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _McpCap implements McpCapability {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NativeCap implements TeamBehaviorCapability {
  const _NativeCap({this.native = true});

  final bool native;

  @override
  bool get supportsNativeTeam => native;

  @override
  bool get longBlockingWaitForMessage => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CliToolRegistry registryWith({
  bool session = true,
  bool skill = true,
  bool mcp = true,
  bool nativeTeam = false,
  bool launch = true,
}) {
  final registry = CliToolRegistry();
  final caps = <CliCapability>[
    if (session) const _SessionCap(),
    if (skill) _SkillCap(),
    if (mcp) _McpCap(),
    if (nativeTeam) const _NativeCap(),
  ];
  registry.register(_FakeDefinition(CliTool.claude, caps: caps));
  registry.register(
    _FakeDefinition(
      CliTool.codex,
      caps: launch ? caps : const <CliCapability>[],
    ),
  );
  return registry;
}

void main() {
  test('generator needs launch, session, skill, and mcp capabilities', () {
    final compatibility = TeamGenerationCompatibility(
      registry: registryWith(mcp: false),
    );
    final result = compatibility.evaluateGenerator(
      preset: preset('gen', CliTool.codex),
    );
    expect(result.isCompatible, isFalse);
    expect(
      result.issues.map((issue) => issue.code),
      contains('generator_mcp_unsupported'),
    );
    expect(result.builderSecurityPolicy, isNotNull);
  });

  test(
    'generator accepts a fully capable cli and never grants full access',
    () {
      final compatibility = TeamGenerationCompatibility(
        registry: registryWith(),
      );
      final result = compatibility.evaluateGenerator(
        preset: preset('gen', CliTool.codex),
      );
      expect(result.isCompatible, isTrue);
      expect(
        result.builderSecurityPolicy,
        isNot(LaunchSecurityPolicy.fullAccess),
      );
    },
  );

  test('native pool requires one native-team-capable cli', () {
    final compatibility = TeamGenerationCompatibility(
      registry: registryWith(nativeTeam: false),
    );
    final result = compatibility.evaluateTeamPool(
      mode: TeamMode.native,
      nativeCli: CliTool.codex,
      pool: [poolEntry('codex', CliTool.codex)],
    );
    expect(
      result.issues.map((issue) => issue.code),
      contains('native_team_unsupported'),
    );
  });

  test('mixed pool may span launchable clis', () {
    final compatibility = TeamGenerationCompatibility(
      registry: registryWith(nativeTeam: false),
    );
    final result = compatibility.evaluateTeamPool(
      mode: TeamMode.mixed,
      nativeCli: CliTool.claude,
      pool: [
        poolEntry('claude-strong', CliTool.claude),
        poolEntry('codex-fast', CliTool.codex),
      ],
    );
    expect(result.isCompatible, isTrue);
  });

  test('empty pool reports model_pool_empty', () {
    final compatibility = TeamGenerationCompatibility(registry: registryWith());
    final result = compatibility.evaluateTeamPool(
      mode: TeamMode.mixed,
      nativeCli: CliTool.claude,
      pool: const [],
    );
    expect(
      result.issues.map((issue) => issue.code),
      contains('model_pool_empty'),
    );
  });
}
