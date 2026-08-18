import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/assemblers/hook_assembler.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/hook_contribution_provider.dart';
import 'package:teampilot/services/resource/providers/endpoint_hook_contribution_provider.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

void main() {
  const assembler = HookAssembler();

  test('deduplicates identical managed and user entries', () async {
    const entry = HookEntry(
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
            const HookEntry(
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
            const HookEntry(
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
            const HookEntry(
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
      const HookEntry(
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
      const HookEntry(
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

  test('fails closed when a required event is unsupported by the CLI', () {
    final contribution = _contribution(
      const HookEntry(
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
              const HookEntry(
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
  _Provider(this.providerId, this.entries, {this.delay})
    : failure = null,
      optional = false;

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
