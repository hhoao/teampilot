import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/mcp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/resource/cli_resource_provisioner.dart';
import 'package:teampilot/services/resource/contribution/prompt_document.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/mcp_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/prompt_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/resource/resource_scope.dart';
import 'package:teampilot/services/resource/resource_materializer.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test(
    'assembles registry providers before injected providers and materializes after all four assemblers',
    () async {
      final events = <String>[];
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/sources/skill');
      final registry = _registry([
        _RecordingPromptProvider('registry-prompt', events),
        _RecordingSkillProvider('registry-skill', events),
        _RecordingMcpProvider('registry-mcp', events),
        _RecordingHookProvider('registry-hook', events),
        _RecordingPromptCapability(events),
        _RecordingSkillCapability(events),
        _RecordingMcpCapability(events),
        _RecordingHookCapability(events),
      ]);
      final injected = ResourceProviderSet(
        prompts: [_RecordingPromptProvider('injected-prompt', events)],
        skills: [_RecordingSkillProvider('injected-skill', events)],
        mcp: [_RecordingMcpProvider('injected-mcp', events)],
        hooks: [_RecordingHookProvider('injected-hook', events)],
      );

      final report = await CliResourceProvisioner(
        fs: fs,
        registry: registry,
      ).provision(_context(fs: fs, registry: registry, injected: injected));

      expect(report.hardDiagnostics, isEmpty);
      expect(events.sublist(0, 8), [
        'provide:registry-prompt',
        'provide:injected-prompt',
        'provide:registry-skill',
        'provide:injected-skill',
        'provide:registry-mcp',
        'provide:injected-mcp',
        'provide:registry-hook',
        'provide:injected-hook',
      ]);
      expect(
        events.skip(8),
        containsAllInOrder([
          'materialize:skill',
          'materialize:prompt',
          'materialize:mcp',
          'materialize:hook',
          'materialize:mcp-credentials',
        ]),
      );
      expect(
        report.materializations.keys,
        containsAll(ResourceContributionKind.values),
      );
    },
  );

  test(
    'non-empty unsupported resources report a structured hard diagnostic',
    () async {
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/sources/skill');
      final registry = _registry([]);

      final report = await CliResourceProvisioner(fs: fs, registry: registry)
          .provision(
            _context(
              fs: fs,
              registry: registry,
              injected: ResourceProviderSet(
                skills: [
                  _RecordingSkillProvider(
                    'injected-skill',
                    <String>[],
                    nonEmpty: true,
                  ),
                ],
              ),
            ),
          );

      expect(report.hardDiagnostics, hasLength(1));
      expect(report.hardDiagnostics.single, isA<ResourceAssemblyError>());
      expect(
        report.hardDiagnostics.single.resourceKind,
        ResourceContributionKind.skill,
      );
      expect(
        (report.hardDiagnostics.single as ResourceAssemblyError).errorKind,
        ResourceAssemblyErrorKind.unsupported,
      );
    },
  );

  test(
    'empty unsupported resources are a no-op and do not erase unrelated config',
    () async {
      final fs = InMemoryFilesystem();
      await fs.writeString('/config/unrelated.json', 'keep');
      final registry = _registry([]);

      final report = await CliResourceProvisioner(
        fs: fs,
        registry: registry,
      ).provision(_context(fs: fs, registry: registry));

      expect(report.hardDiagnostics, isEmpty);
      expect(await fs.readString('/config/unrelated.json'), 'keep');
      expect(
        report.materializations.values.every((result) => !result.attempted),
        isTrue,
      );
    },
  );

  test(
    'repeated provisioning is idempotent and only provisions the requested CLI',
    () async {
      final fs = InMemoryFilesystem();
      await fs.ensureDir('/sources/skill');
      final events = <String>[];
      final registry = _registry([
        _RecordingSkillProvider('skill', events),
        _RecordingSkillCapability(events),
      ]);
      final provisioner = CliResourceProvisioner(fs: fs, registry: registry);
      final context = _context(fs: fs, registry: registry);

      final first = await provisioner.provision(context);
      final firstEntries = await fs.listDir('/config/skills');
      final second = await provisioner.provision(context);
      final secondEntries = await fs.listDir('/config/skills');

      expect(first.hardDiagnostics, isEmpty);
      expect(second.hardDiagnostics, isEmpty);
      expect(
        secondEntries.map((entry) => entry.name),
        firstEntries.map((entry) => entry.name),
      );
      expect(
        events.where((event) => event.startsWith('provide:skill')),
        hasLength(2),
      );
      expect(events, everyElement(isNot(contains('opencode'))));
    },
  );

  test(
    'provider failures are returned as hard structured diagnostics',
    () async {
      final fs = InMemoryFilesystem();
      final registry = _registry([_FailingPromptProvider()]);

      final report = await CliResourceProvisioner(
        fs: fs,
        registry: registry,
      ).provision(_context(fs: fs, registry: registry));

      expect(report.hardDiagnostics, hasLength(1));
      expect(
        report.hardDiagnostics.single.resourceKind,
        ResourceContributionKind.prompt,
      );
      expect(report.hardDiagnostics.single.providerId, 'failing-prompt');
    },
  );
}

CliResourceProvisionContext _context({
  required InMemoryFilesystem fs,
  required CliToolRegistry registry,
  ResourceProviderSet injected = ResourceProviderSet.empty,
}) => CliResourceProvisionContext(
  cli: CliTool.claude,
  scope: const SimpleResourceScope(bundle: ConfigBundle()),
  runtimeBundle: const ConfigBundle(),
  fs: fs,
  layout: RuntimeLayout(teampilotRoot: '/runtime', fs: fs),
  configDir: '/config',
  appConfigDir: '/app',
  resourceProviders: injected,
);

CliToolRegistry _registry(List<CliCapability> capabilities) =>
    CliToolRegistry()..register(_Tool(capabilities));

final class _Tool implements CliToolDefinition {
  const _Tool(this.capabilities);
  @override
  final List<CliCapability> capabilities;
  @override
  CliTool get id => CliTool.claude;
  @override
  bool get isLaunchSupported => true;
}

final class _RecordingPromptProvider
    implements CliCapability, PromptContributionProvider {
  const _RecordingPromptProvider(this.providerId, this.events);
  @override
  final String providerId;
  final List<String> events;
  @override
  Iterable<PromptContribution> provide(PromptProviderContext context) {
    events.add('provide:$providerId');
    return [
      PromptContribution(
        id: providerId,
        title: providerId,
        content: providerId,
        scope: PromptScope.cli,
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.cliBuiltIn,
        ),
      ),
    ];
  }
}

final class _FailingPromptProvider
    implements CliCapability, PromptContributionProvider {
  @override
  String get providerId => 'failing-prompt';
  @override
  Future<Iterable<PromptContribution>> provide(PromptProviderContext context) =>
      Future.error(StateError('boom'));
}

final class _RecordingSkillProvider
    implements CliCapability, SkillContributionProvider {
  const _RecordingSkillProvider(
    this.providerId,
    this.events, {
    this.nonEmpty = false,
  });
  @override
  final String providerId;
  final List<String> events;
  final bool nonEmpty;
  @override
  Iterable<SkillContribution> provide(SkillProviderContext context) {
    events.add('provide:$providerId');
    if (!nonEmpty && providerId.contains('injected')) return const [];
    return [
      SkillContribution(
        id: providerId,
        invocationName: providerId,
        artifact: const SkillDirectoryArtifact('/sources/skill'),
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.catalog,
        ),
      ),
    ];
  }
}

final class _RecordingMcpProvider
    implements CliCapability, McpContributionProvider {
  const _RecordingMcpProvider(this.providerId, this.events);
  @override
  final String providerId;
  final List<String> events;
  @override
  Iterable<McpContribution> provide(McpProviderContext context) {
    events.add('provide:$providerId');
    return [
      McpContribution(
        sourceId: providerId,
        server: StdioMcpServer(name: providerId, command: 'server'),
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.catalog,
        ),
      ),
    ];
  }
}

final class _RecordingHookProvider
    implements CliCapability, HookContributionProvider {
  const _RecordingHookProvider(this.providerId, this.events);
  @override
  final String providerId;
  final List<String> events;
  @override
  Iterable<HookContribution> provide(HookProviderContext context) {
    events.add('provide:$providerId');
    return [
      HookContribution(
        sourceId: providerId,
        entry: HookEntry(
          id: providerId,
          source: HookSource.managed,
          event: HookEvent.stop,
          action: const CommandHookAction.raw('true'),
        ),
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.managed,
        ),
      ),
    ];
  }
}

final class _RecordingPromptCapability implements PromptCapability {
  const _RecordingPromptCapability(this.events);
  final List<String> events;
  @override
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx, {
    required PromptDocument document,
  }) async {
    events.add('materialize:prompt');
    return const PromptMaterializeResult(written: true);
  }
}

final class _RecordingSkillCapability
    with SkillCapabilityMaterializationMixin
    implements SkillCapability {
  const _RecordingSkillCapability(this.events);
  final List<String> events;
  @override
  String get skillsSubdir => 'skills';
  @override
  ResourceRepresentation get skillsRepresentation =>
      ResourceRepresentation.linkedDirectory;
  @override
  String get skillInvocationPrefix => '/';
  @override
  String skillInvocationText(String skillName, {String? namespace}) =>
      '/$skillName';
  @override
  Future<MaterializeResult> materializeSkills({
    required Filesystem fs,
    required String configDir,
    required Iterable<SkillContribution> contributions,
    ResourceMaterializer? materializer,
  }) {
    events.add('materialize:skill');
    return super.materializeSkills(
      fs: fs,
      configDir: configDir,
      contributions: contributions,
      materializer: materializer,
    );
  }
}

final class _RecordingMcpCapability implements McpCapability {
  const _RecordingMcpCapability(this.events);
  final List<String> events;
  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
    String? outputBasename,
  }) async {
    events.add('materialize:mcp');
  }

  @override
  Future<void> mergeAppCredentials({
    required Filesystem fs,
    required String appConfigDir,
    required String sessionConfigDir,
    String? fallbackAppConfigDir,
  }) async {
    events.add('materialize:mcp-credentials');
  }
}

final class _RecordingHookCapability implements HookCapability {
  const _RecordingHookCapability(this.events);
  final List<String> events;
  @override
  String? nativeEvent(HookEvent event) => event.name;
  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => true;
  @override
  bool get supportsPolicy => true;
  @override
  bool supportsEvent(HookEvent event) => nativeEvent(event) != null;
  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) {
    events.add('materialize:hook');
    return const HookWriteResult();
  }
}
