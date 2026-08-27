import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/assemblers/hook_assembler.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/resource/providers/endpoint_hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/runtime_event_hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/bus_awareness_hook_contribution_provider.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

void main() {
  const assembler = HookAssembler();

  test('deduplicates identical managed and user entries', () async {
    final entry = HookEntry(
      id: 'user-hook',
      source: HookSource.userLibrary,
      event: HookEvent.stop,
      action: CommandHookAction.raw(' echo stop '),
    );
    final result = await assembler.assemble(
      context: HookProviderContext(cli: CliTool.claude),
      providers: [
        _Provider('user-library', [
          _contribution(entry, ResourceOriginKind.workspace, 'user-hook'),
        ]),
        _Provider('managed', [
          _contribution(
            HookEntry(
              id: 'managed-hook',
              source: HookSource.managed,
              event: HookEvent.stop,
              action: CommandHookAction.raw('echo stop'),
            ),
            ResourceOriginKind.managed,
            'managed-hook',
          ),
        ]),
      ],
    );

    expect(result.entries, hasLength(1));
    expect(result.entries.single.id, 'user-hook');
  });

  test('keeps distinct hooks on the same event in provider order', () async {
    final result = await assembler.assemble(
      context: HookProviderContext(cli: CliTool.claude),
      providers: [
        _Provider('slow', [
          _contribution(
            HookEntry(
              id: 'first',
              source: HookSource.userLibrary,
              event: HookEvent.stop,
              action: CommandHookAction.raw('first'),
            ),
            ResourceOriginKind.workspace,
            'first',
          ),
        ], delay: const Duration(milliseconds: 20)),
        _Provider('fast', [
          _contribution(
            HookEntry(
              id: 'second',
              source: HookSource.userLibrary,
              event: HookEvent.stop,
              action: CommandHookAction.raw('second'),
            ),
            ResourceOriginKind.workspace,
            'second',
          ),
        ]),
      ],
    );

    expect(result.entries.map((entry) => entry.id), ['first', 'second']);
  });

  test('reports same identity conflicts with provider and source metadata', () {
    final first = _contribution(
      HookEntry(
        id: 'first',
        source: HookSource.userLibrary,
        event: HookEvent.preToolUse,
        matcher: 'Bash',
        action: CommandHookAction.raw('check'),
      ),
      ResourceOriginKind.workspace,
      'first-source',
    );
    final second = _contribution(
      HookEntry(
        id: 'second',
        source: HookSource.managed,
        event: HookEvent.preToolUse,
        matcher: 'Bash',
        timeout: Duration(seconds: 30),
        action: CommandHookAction.raw('check'),
      ),
      ResourceOriginKind.managed,
      'managed-source',
    );

    expect(
      () => assembler.assemble(
        context: HookProviderContext(cli: CliTool.claude),
        providers: [
          _Provider('user-provider', [first]),
          _Provider('managed-provider', [second]),
        ],
      ),
      throwsA(
        isA<ResourceAssemblyException>().having(
          (error) => error.diagnostics.single,
          'diagnostic',
          isA<ResourceAssemblyError>()
              .having(
                (error) => error.errorKind,
                'kind',
                ResourceAssemblyErrorKind.conflict,
              )
              .having(
                (error) => error.providerId,
                'provider',
                'managed-provider',
              )
              .having((error) => error.sourceId, 'source', 'managed-source')
              .having(
                (error) => error.previousProviderId,
                'previous provider',
                'user-provider',
              )
              .having(
                (error) => error.previousSourceId,
                'previous source',
                'first-source',
              ),
        ),
      ),
    );
  });

  test('optional hook conflict warns and required entry wins', () async {
    final required = _contribution(
      HookEntry(
        id: 'required',
        source: HookSource.userLibrary,
        event: HookEvent.stop,
        action: CommandHookAction.raw('echo stop'),
        timeout: Duration(seconds: 5),
      ),
      ResourceOriginKind.workspace,
      'required-source',
    );
    final optional = _contribution(
      HookEntry(
        id: 'optional',
        source: HookSource.plugin,
        event: HookEvent.stop,
        action: CommandHookAction.raw('echo stop'),
        timeout: Duration(seconds: 10),
      ),
      ResourceOriginKind.plugin,
      'optional-source',
    );

    final result = await assembler.assemble(
      context: HookProviderContext(cli: CliTool.claude),
      providers: [
        _Provider('required', [required]),
        _Provider('plugin', [optional], optional: true),
      ],
    );

    expect(result.entries.single.id, 'required');
    expect(result.errors, isEmpty);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.providerId, 'plugin');
    expect(result.warnings.single.sourceId, 'optional-source');
    expect(result.warnings.single.previousProviderId, 'required');
    expect(result.warnings.single.previousSourceId, 'required-source');
    expect(result.warnings.single.message, contains('Optional hook plugin/'));
    expect(
      result.warnings.single.message,
      contains('required hook required/required-source'),
    );
  });

  test(
    'required hook replaces earlier optional conflict without fatal',
    () async {
      final optional = _contribution(
        HookEntry(
          id: 'optional',
          source: HookSource.extension,
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo stop'),
          timeout: Duration(seconds: 10),
        ),
        ResourceOriginKind.extension,
        'optional-source',
      );
      final required = _contribution(
        HookEntry(
          id: 'required',
          source: HookSource.userLibrary,
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo stop'),
          timeout: Duration(seconds: 5),
        ),
        ResourceOriginKind.workspace,
        'required-source',
      );

      final result = await assembler.assemble(
        context: HookProviderContext(cli: CliTool.claude),
        providers: [
          _Provider('extension', [optional], optional: true),
          _Provider('required', [required]),
        ],
      );

      expect(result.entries.single.id, 'required');
      expect(result.errors, isEmpty);
      expect(result.warnings.single.providerId, 'required');
      expect(result.warnings.single.sourceId, 'required-source');
      expect(result.warnings.single.previousProviderId, 'extension');
      expect(result.warnings.single.previousSourceId, 'optional-source');
      expect(
        result.warnings.single.message,
        contains('Optional hook extension/optional-source'),
      );
      expect(
        result.warnings.single.message,
        contains('required required/required-source'),
      );
    },
  );

  test(
    'optional hook conflicts remain warnings with both sides locatable',
    () async {
      final first = _contribution(
        HookEntry(
          id: 'first-optional',
          source: HookSource.extension,
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo stop'),
          timeout: Duration(seconds: 5),
        ),
        ResourceOriginKind.extension,
        'first-source',
      );
      final second = _contribution(
        HookEntry(
          id: 'second-optional',
          source: HookSource.plugin,
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo stop'),
          timeout: Duration(seconds: 10),
        ),
        ResourceOriginKind.plugin,
        'second-source',
      );

      final result = await assembler.assemble(
        context: HookProviderContext(cli: CliTool.claude),
        providers: [
          _Provider('extension-provider', [first], optional: true),
          _Provider('plugin-provider', [second], optional: true),
        ],
      );

      expect(result.entries.map((entry) => entry.id), ['first-optional']);
      expect(result.errors, isEmpty);
      final warning = result.warnings.single;
      expect(warning.providerId, 'plugin-provider');
      expect(warning.sourceId, 'second-source');
      expect(warning.previousProviderId, 'extension-provider');
      expect(warning.previousSourceId, 'first-source');
      expect(warning.message, contains('Optional hook'));
      expect(warning.message, contains('plugin-provider/second-source'));
      expect(warning.message, contains('extension-provider/first-source'));
    },
  );

  test('fails closed when a required event is unsupported by the CLI', () {
    final contribution = _contribution(
      HookEntry(
        id: 'required',
        source: HookSource.userLibrary,
        event: HookEvent.stopFailure,
        action: CommandHookAction.raw('required'),
      ),
      ResourceOriginKind.workspace,
      'required-source',
    );

    expect(
      () => assembler.assemble(
        context: HookProviderContext(cli: CliTool.opencode),
        providers: [
          _Provider('user-library', [contribution]),
        ],
      ),
      throwsA(
        isA<ResourceAssemblyException>().having(
          (error) => error.diagnostics.single.errorKind,
          'kind',
          ResourceAssemblyErrorKind.unsupported,
        ),
      ),
    );
  });

  test('bus awareness contributes sessionStart for Claude', () async {
    const member = TeamMemberConfig(id: 'implementer', name: 'Implementer');
    final result = await assembler.assemble(
      context: HookProviderContext(cli: CliTool.claude, member: member),
      providers: [BusAwarenessHookContributionProvider()],
    );
    expect(result.entries.map((entry) => entry.event), [
      HookEvent.sessionStart,
    ]);
    expect(result.entries.single.id, 'teampilot-bus-awareness-sessionStart');
  });

  test('bus awareness contributes nothing for OpenCode', () async {
    const member = TeamMemberConfig(id: 'implementer', name: 'Implementer');
    final result = await assembler.assemble(
      context: HookProviderContext(
        cli: CliTool.opencode,
        member: member,
        supportsHttp: false,
      ),
      providers: [BusAwarenessHookContributionProvider()],
    );
    expect(result.entries, isEmpty);
    expect(result.assembly.errors, isEmpty);
  });

  test('filters unsupported managed endpoint events for Cursor', () async {
    final result = await assembler.assemble(
      context: HookProviderContext(cli: CliTool.cursor),
      providers: [
        BusIdleHookContributionProvider(
          endpoint: const MemberBusIdleEndpoint(url: 'http://127.0.0.1:1/idle'),
          memberId: 'm1',
        ),
      ],
    );

    expect(result.entries.map((entry) => entry.event), [HookEvent.stop]);
  });

  test(
    'skips managed HTTP endpoint hooks when the CLI does not support HTTP',
    () async {
      final result = await assembler.assemble(
        context: HookProviderContext(
          cli: CliTool.opencode,
          supportsHttp: false,
        ),
        providers: [
          RuntimeEventHookContributionProvider(
            endpoint: const MemberAgentStatusEndpoint(
              url: 'http://127.0.0.1:1/agent-status',
            ),
            memberId: 'm1',
          ),
          BusIdleHookContributionProvider(
            endpoint: const MemberBusIdleEndpoint(
              url: 'http://127.0.0.1:1/idle',
            ),
            memberId: 'm1',
          ),
        ],
      );

      // HTTP endpoint hooks are dropped for CLIs whose native config cannot
      // express them, while OpenCode's runtime plugin materialization stays:
      // it is contributed through this same profile assembly step
      // (NativePluginHookAction), not as an HTTP hook.
      expect(result.entries.map((entry) => entry.id), [
        'teampilot-runtime-event-plugin',
      ]);
      expect(result.entries.single.action, isA<NativePluginHookAction>());
      expect(result.assembly.errors, isEmpty);
    },
  );

  test('managed provider failure is fail closed', () {
    expect(
      () => assembler.assemble(
        context: HookProviderContext(cli: CliTool.claude),
        providers: [_Provider.failure('managed')],
      ),
      throwsA(
        isA<ResourceAssemblyException>().having(
          (error) => error.diagnostics.single.providerId,
          'provider',
          'managed',
        ),
      ),
    );
  });

  test(
    'optional plugin failure is a warning and does not discard other hooks',
    () async {
      final result = await assembler.assemble(
        context: HookProviderContext(cli: CliTool.claude),
        providers: [
          _Provider.failure('plugin', optional: true),
          _Provider('managed', [
            _contribution(
              HookEntry(
                id: 'managed',
                source: HookSource.managed,
                event: HookEvent.stop,
                action: CommandHookAction.raw('managed'),
              ),
              ResourceOriginKind.managed,
              'managed-source',
            ),
          ]),
        ],
      );

      expect(result.entries.map((entry) => entry.id), ['managed']);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single.providerId, 'plugin');
    },
  );
}

HookContribution _contribution(
  HookEntry entry,
  ResourceOriginKind kind,
  String sourceId,
) => HookContribution(
  sourceId: sourceId,
  entry: entry,
  origin: ContributionOrigin(
    providerId: sourceId,
    kind: kind,
    sourceId: sourceId,
  ),
);

final class _Provider
    implements HookContributionProvider, HookContributionProviderOptional {
  _Provider(this.providerId, this.entries, {this.delay, bool optional = false})
    : failure = null,
      optional = optional;

  _Provider.failure(this.providerId, {this.optional = false})
    : entries = const [],
      delay = null,
      failure = StateError('provider failed');

  @override
  final String providerId;

  final List<HookContribution> entries;
  final Duration? delay;
  final Object? failure;

  @override
  final bool optional;

  @override
  Future<Iterable<HookContribution>> provide(
    HookProviderContext context,
  ) async {
    if (delay != null) await Future<void>.delayed(delay!);
    if (failure != null) throw failure!;
    return entries;
  }
}
