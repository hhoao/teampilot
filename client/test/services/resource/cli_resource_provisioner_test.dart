import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/cli/codex/provider/codex_hook_writer.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_capability.dart';
import 'package:teampilot/services/resource/providers/endpoint_hook_contribution_provider.dart';
import 'package:teampilot/services/cli/registry/capabilities/mcp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/hook_registry.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_scope.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/resource/cli_resource_provisioner.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/mcp_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/catalog_mcp_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/skill_contribution_provider.dart';
import 'package:teampilot/services/resource/resource_provider_set.dart';
import 'package:teampilot/services/resource/resource_scope.dart';
import 'package:teampilot/services/resource/resource_materializer.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/cursor_lifecycle_test_paths.dart';

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
      ).provision(_context(fs: fs, injected: injected));

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
        report.hardDiagnostics.single.errorKind,
        ResourceAssemblyErrorKind.unsupported,
      );
      final result = report.materializations[ResourceContributionKind.skill]!;
      expect(result.attempted, isTrue);
      expect(result.materialized, isFalse);
      expect(result.diagnostics, hasLength(1));
    },
  );

  test('all unsupported non-empty kinds retain per-kind diagnostics', () async {
    final fs = InMemoryFilesystem();
    final registry = _registry([]);
    final report = await CliResourceProvisioner(fs: fs, registry: registry)
        .provision(
          _context(
            fs: fs,
            injected: ResourceProviderSet(
              prompts: [_RecordingPromptProvider('prompt', <String>[])],
              skills: [
                _RecordingSkillProvider('skill', <String>[], nonEmpty: true),
              ],
              mcp: [_RecordingMcpProvider('mcp', <String>[])],
              hooks: [_RecordingHookProvider('hook', <String>[])],
            ),
          ),
        );

    for (final kind in ResourceContributionKind.values) {
      final result = report.materializations[kind]!;
      expect(result.attempted, isTrue, reason: kind.name);
      expect(result.materialized, isFalse, reason: kind.name);
      expect(result.diagnostics, isNotEmpty, reason: kind.name);
    }
  });

  test(
    'empty unsupported resources are a no-op and do not erase unrelated config',
    () async {
      final fs = InMemoryFilesystem();
      await fs.writeString('/config/unrelated.json', 'keep');
      final registry = _registry([]);

      final report = await CliResourceProvisioner(
        fs: fs,
        registry: registry,
      ).provision(_context(fs: fs));

      expect(report.hardDiagnostics, isEmpty);
      expect(await fs.readString('/config/unrelated.json'), 'keep');
      expect(
        report.materializations.keys,
        containsAll(ResourceContributionKind.values),
      );
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
      final context = _context(fs: fs);

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
      ).provision(_context(fs: fs));

      expect(report.hardDiagnostics, hasLength(1));
      expect(
        report.hardDiagnostics.single.resourceKind,
        ResourceContributionKind.prompt,
      );
      expect(report.hardDiagnostics.single.providerId, 'failing-prompt');
    },
  );

  test(
    'assembly failure retains attempted failed materialization state',
    () async {
      final fs = InMemoryFilesystem();
      final report =
          await CliResourceProvisioner(
            fs: fs,
            registry: _registry([]),
          ).provision(
            _context(
              fs: fs,
              injected: ResourceProviderSet(
                prompts: [_FailingPromptProvider()],
              ),
            ),
          );

      final result = report.materializations[ResourceContributionKind.prompt]!;
      expect(result.attempted, isTrue);
      expect(result.materialized, isFalse);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.providerId, 'failing-prompt');
    },
  );

  test(
    'provisionHooks retains attempted failed materialization state',
    () async {
      final fs = InMemoryFilesystem();
      final report = await CliResourceProvisioner(
        fs: fs,
        registry: _registry([_FailingHookProvider()]),
      ).provisionHooks(_context(fs: fs));

      expect(report.hardDiagnostics, hasLength(1));
      final result = report.materializations[ResourceContributionKind.hook]!;
      expect(result.attempted, isTrue);
      expect(result.materialized, isFalse);
      expect(result.diagnostics, hasLength(1));
      expect(result.diagnostics.single.providerId, 'failing-hook');
    },
  );

  test(
    'resolves each injected MCP source once before materialization',
    () async {
      final fs = InMemoryFilesystem();
      var calls = 0;
      final provider = _CountingMcpProvider(() => calls++);
      final registry = _registry([_RecordingMcpCapability(<String>[])]);

      final report = await CliResourceProvisioner(fs: fs, registry: registry)
          .provision(
            _context(
              fs: fs,
              injected: ResourceProviderSet(mcp: [provider]),
            ),
          );

      expect(report.hardDiagnostics, isEmpty);
      expect(calls, 1);
    },
  );

  test(
    'uses the requested real CLI capability for every launchable CLI',
    () async {
      final registry = CliToolRegistry.builtIn();
      const launchable = [
        CliTool.claude,
        CliTool.flashskyai,
        CliTool.codex,
        CliTool.opencode,
        CliTool.cursor,
      ];
      final selected = <CliTool>[];

      for (final cli in launchable) {
        final fs = InMemoryFilesystem();
        final report = await CliResourceProvisioner(fs: fs, registry: registry)
            .provision(
              _context(
                fs: fs,
                cli: cli,
                configDir: '/config-${cli.value}',
                injected: ResourceProviderSet(
                  mcp: [
                    _McpSelectionProvider(
                      (selectedCli) => selected.add(selectedCli),
                    ),
                  ],
                ),
              ),
            );

        expect(report.hardDiagnostics, isEmpty, reason: cli.value);
        expect(
          report.materializations[ResourceContributionKind.mcp]!.materialized,
          isTrue,
          reason: cli.value,
        );
      }

      expect(selected, launchable);
    },
  );

  test(
    'codex agent-status hooks wrap scripts with bash so they do not need +x',
    () async {
      final fs = InMemoryFilesystem();
      final registry = _registry(
        [const CodexHookWriter()],
        id: CliTool.codex,
      );
      final report = await CliResourceProvisioner(fs: fs, registry: registry)
          .provision(
            _context(
              fs: fs,
              cli: CliTool.codex,
              injected: ResourceProviderSet(
                hooks: [
                  AgentStatusHookContributionProvider(
                    endpoint: const MemberAgentStatusEndpoint(
                      url: 'http://127.0.0.1:9/agent-status',
                    ),
                    memberId: 'm1',
                  ),
                ],
              ),
            ),
          );

      expect(report.hardDiagnostics, isEmpty);
      final toml = await fs.readString('/config/config.toml');
      expect(toml, isNotNull);
      expect(toml, contains('bash '));
      expect(
        toml,
        contains('teampilot-http-teampilot-agent-status-preToolUse'),
      );
      expect(
        toml,
        isNot(contains(RegExp(r'command = "/config/hooks/[^"]+\.sh"'))),
      );
    },
  );

  test(
    'materializes hook fragments and generated scripts to the target',
    () async {
      final fs = InMemoryFilesystem();
      final registry = _registry([_WritingHookCapability()]);
      final report = await CliResourceProvisioner(fs: fs, registry: registry)
          .provision(
            _context(
              fs: fs,
              injected: ResourceProviderSet(
                hooks: [_RecordingHookProvider('hook', <String>[])],
              ),
            ),
          );

      expect(report.hardDiagnostics, isEmpty);
      expect(
        report.materializations[ResourceContributionKind.hook]!.materialized,
        isTrue,
      );
      expect(await fs.readString('/config/settings.json'), contains('hooks'));
      expect(
        await fs.readString('/config/hooks/generated.sh'),
        'echo generated',
      );
    },
  );

  test(
    'materializes hook fragments at the explicit target config path',
    () async {
      final fs = InMemoryFilesystem();
      final report =
          await CliResourceProvisioner(
            fs: fs,
            registry: _registry([_WritingHookCapability()]),
          ).provision(
            CliResourceProvisionContext(
              cli: CliTool.claude,
              scope: const SimpleResourceScope(bundle: ConfigBundle()),
              runtimeBundle: const ConfigBundle(),
              fs: fs,
              layout: RuntimeLayout(teampilotRoot: '/runtime', fs: fs),
              configDir: '/config',
              hookConfigPath: '/config/settings/member.json',
              resourceProviders: ResourceProviderSet(
                hooks: [_RecordingHookProvider('hook', <String>[])],
              ),
            ),
          );

      expect(report.hardDiagnostics, isEmpty);
      expect(
        await fs.readString('/config/settings/member.json'),
        contains('hooks'),
      );
      expect(await fs.readString('/config/settings.json'), isNull);
    },
  );

  test('preserves unrelated hook config fragments and is idempotent', () async {
    final fs = InMemoryFilesystem();
    final settingsPath = '/config/settings.json';
    await fs.ensureDir('/config');
    await fs.atomicWrite(
      settingsPath,
      jsonEncode({
        'permissions': {
          'allow': ['Bash'],
        },
        'hooks': {
          'existing': ['keep-me'],
        },
      }),
    );
    final provisioner = CliResourceProvisioner(
      fs: fs,
      registry: _registry([_WritingHookCapability()]),
    );
    final injected = ResourceProviderSet(
      hooks: [_RecordingHookProvider('hook', <String>[])],
    );

    final first = await provisioner.provision(
      _context(fs: fs, injected: injected),
    );
    final firstText = await fs.readString(settingsPath);
    final settings = jsonDecode(firstText!) as Map<String, Object?>;
    expect(settings['permissions'], {
      'allow': ['Bash'],
    });
    expect((settings['hooks'] as Map)['existing'], ['keep-me']);
    expect((settings['hooks'] as Map)['stop'], isNotNull);
    expect(
      first.materializations[ResourceContributionKind.hook]!.materialized,
      isTrue,
    );

    final second = await provisioner.provision(
      _context(fs: fs, injected: injected),
    );
    expect(await fs.readString(settingsPath), firstText);
    expect(second.hardDiagnostics, isEmpty);
  });

  test('merges MCP credentials only for valid catalog contributions', () async {
    final fs = InMemoryFilesystem();
    final events = <String>[];
    final registry = _registry([_RecordingMcpCapability(events)]);
    final provisioner = CliResourceProvisioner(fs: fs, registry: registry);

    await provisioner.provision(
      _context(
        fs: fs,
        injected: ResourceProviderSet(mcp: [_ManagedMcpProvider()]),
      ),
    );
    expect(events, isNot(contains('materialize:mcp-credentials')));

    events.clear();
    await provisioner.provision(
      _context(
        fs: fs,
        injected: ResourceProviderSet(
          mcp: [_RecordingMcpProvider('catalog', events)],
        ),
      ),
    );
    expect(events, contains('materialize:mcp-credentials'));
  });

  test(
    'team identity catalog snapshots still trigger credential merge',
    () async {
      final fs = InMemoryFilesystem();
      await fs.atomicWrite(
        '/team-mcp.json',
        jsonEncode({
          'mcpServers': {
            'team-catalog-server': {'command': 'server'},
          },
        }),
      );
      final events = <String>[];
      final report =
          await CliResourceProvisioner(
            fs: fs,
            registry: _registry([_RecordingMcpCapability(events)]),
          ).provision(
            _context(
              fs: fs,
              injected: ResourceProviderSet(
                mcp: [
                  CatalogMcpContributionProvider(
                    fs: fs,
                    snapshotPath: '/team-mcp.json',
                    originKind: ResourceOriginKind.team,
                  ),
                ],
              ),
            ),
          );

      expect(report.hardDiagnostics, isEmpty);
      expect(events, contains('materialize:mcp-credentials'));
    },
  );

  test('prompt materialization uses the complete target context', () async {
    final fs = InMemoryFilesystem();
    final paths = CursorLifecycleTestPaths(
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/runtime', fs: fs),
    );
    final member = const TeamMemberConfig(id: 'alice', name: 'Alice');
    PromptMaterializeContext? observedContext;
    final report =
        await CliResourceProvisioner(
          fs: fs,
          registry: _registry([
            _WritingPromptCapability((context) => observedContext = context),
          ]),
        ).provision(
          CliResourceProvisionContext(
            cli: CliTool.claude,
            scope: const SimpleResourceScope(bundle: ConfigBundle()),
            runtimeBundle: const ConfigBundle(),
            fs: fs,
            layout: RuntimeLayout(teampilotRoot: '/runtime', fs: fs),
            configDir: '/config',
            paths: paths,
            launchScope: const LaunchProfileScope(
              workspaceId: 'workspace',
              teamId: 'workspace',
              sessionId: 'session',
              cliTeamName: 'session',
            ),
            member: member,
            forceTeamLeadDelegateMode: true,
            mixed: true,
            pushDelivery: true,
            resourceProviders: ResourceProviderSet(
              prompts: [_RecordingPromptProvider('prompt', <String>[])],
            ),
          ),
        );

    expect(report.hardDiagnostics, isEmpty);
    expect(observedContext?.member, member);
    expect(observedContext?.forceTeamLeadDelegateMode, isTrue);
    expect(observedContext?.mixed, isTrue);
    expect(observedContext?.pushDelivery, isTrue);
    expect(
      report.materializations[ResourceContributionKind.prompt]!.materialized,
      isTrue,
    );
    final promptPath = paths.pathContext.join(
      paths.sessionToolDir('workspace', 'session', 'claude'),
      'prompts/role.md',
    );
    expect(report.promptMaterialization?.environment, {
      'TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE': promptPath,
    });
    expect(await fs.readString(promptPath), 'prompt');
  });
}

CliResourceProvisionContext _context({
  required InMemoryFilesystem fs,
  CliTool cli = CliTool.claude,
  String configDir = '/config',
  ResourceProviderSet injected = ResourceProviderSet.empty,
}) => CliResourceProvisionContext(
  cli: cli,
  scope: const SimpleResourceScope(bundle: ConfigBundle()),
  runtimeBundle: const ConfigBundle(),
  fs: fs,
  layout: RuntimeLayout(teampilotRoot: '/runtime', fs: fs),
  configDir: configDir,
  appConfigDir: '/app',
  resourceProviders: injected,
);

CliToolRegistry _registry(
  List<CliCapability> capabilities, {
  CliTool id = CliTool.claude,
}) => CliToolRegistry()..register(_Tool(capabilities, id: id));

final class _Tool implements CliToolDefinition {
  const _Tool(this.capabilities, {this.id = CliTool.claude});
  @override
  final List<CliCapability> capabilities;
  @override
  final CliTool id;
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

final class _FailingHookProvider
    implements CliCapability, HookContributionProvider {
  @override
  String get providerId => 'failing-hook';

  @override
  Future<Iterable<HookContribution>> provide(HookProviderContext context) =>
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
        hasCatalogCredentialSource: true,
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.catalog,
        ),
      ),
    ];
  }
}

final class _CountingMcpProvider implements McpContributionProvider {
  _CountingMcpProvider(this.onProvide);
  final void Function() onProvide;

  @override
  String get providerId => 'counting-mcp';

  @override
  Iterable<McpContribution> provide(McpProviderContext context) {
    onProvide();
    return [
      McpContribution(
        sourceId: 'counted',
        server: StdioMcpServer(name: 'counted', command: 'server'),
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.catalog,
        ),
      ),
    ];
  }
}

final class _McpSelectionProvider implements McpContributionProvider {
  _McpSelectionProvider(this.onSelected);
  final void Function(CliTool cli) onSelected;

  @override
  String get providerId => 'actual-cli-mcp';

  @override
  Iterable<McpContribution> provide(McpProviderContext context) {
    onSelected(context.cli);
    return [
      McpContribution(
        sourceId: context.cli.value,
        server: StdioMcpServer(name: context.cli.value, command: 'server'),
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.managed,
        ),
      ),
    ];
  }
}

final class _ManagedMcpProvider implements McpContributionProvider {
  @override
  String get providerId => 'managed-mcp';

  @override
  Iterable<McpContribution> provide(McpProviderContext context) => [
    McpContribution(
      sourceId: 'managed',
      server: StdioMcpServer(name: 'managed', command: 'server'),
      origin: const ContributionOrigin(
        providerId: 'managed-mcp',
        kind: ResourceOriginKind.managed,
      ),
    ),
  ];
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

final class _WritingPromptCapability implements PromptCapability {
  _WritingPromptCapability([this.onContext]);

  final void Function(PromptMaterializeContext context)? onContext;

  @override
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx, {
    required PromptDocument document,
  }) async {
    onContext?.call(ctx);
    final paths = ctx.paths!;
    final path = paths.pathContext.join(
      paths.sessionToolDir(
        ctx.scope!.workspaceId,
        ctx.scope!.sessionId,
        'claude',
      ),
      'prompts/role.md',
    );
    await paths.fs.ensureDir(paths.pathContext.dirname(path));
    await paths.fs.atomicWrite(path, document.content);
    return PromptMaterializeResult(
      written: true,
      environment: {'TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE': path},
    );
  }
}

final class _WritingHookCapability implements HookCapability {
  @override
  String? nativeEvent(HookEvent event) => event.name;
  @override
  bool get supportsMatcher => true;
  @override
  bool get supportsHttp => true;
  @override
  bool get supportsPolicy => true;
  @override
  bool supportsEvent(HookEvent event) => true;
  @override
  HookWriteResult render({
    required List<HookEntry> entries,
    required HookRenderContext ctx,
  }) => const HookWriteResult(
    configFragments: {
      'settings.json': {
        'hooks': {'stop': []},
      },
    },
    scripts: [
      GeneratedScript(fileName: 'generated.sh', content: 'echo generated'),
    ],
  );
}
