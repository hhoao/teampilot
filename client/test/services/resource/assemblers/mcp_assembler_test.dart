import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/mcp_server_spec.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/resource/assemblers/mcp_assembler.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/mcp_contribution_provider.dart';

void main() {
  const assembler = McpAssembler();
  final context = McpProviderContext(cli: CliTool.claude);

  test('higher layers replace lower layers by stable server key', () async {
    final result = await assembler.assemble(
      context: context,
      providers: [
        _Provider([
          _contribution('workspace', ResourceOriginKind.workspace, 'low'),
          _contribution('only-workspace', ResourceOriginKind.workspace, 'w'),
        ]),
        _Provider([
          _contribution('expert', ResourceOriginKind.expert, 'expert'),
          _contribution('workspace', ResourceOriginKind.expert, 'high'),
        ]),
        _Provider([
          _contribution('team', ResourceOriginKind.team, 'team'),
          _contribution('workspace', ResourceOriginKind.team, 'highest'),
        ]),
      ],
    );

    expect(result.servers.map((server) => server.name), [
      'workspace',
      'only-workspace',
      'expert',
      'team',
    ]);
    expect((result.servers.first as StdioMcpServer).command, 'highest');
  });

  test('same-layer different payloads throw structured conflict metadata', () {
    expect(
      () => assembler.assemble(
        context: context,
        providers: [
          _Provider([
            _contribution(
              'same',
              ResourceOriginKind.workspace,
              'one',
              'provider-1',
            ),
          ]),
          _Provider([
            _contribution(
              'same',
              ResourceOriginKind.workspace,
              'two',
              'provider-2',
            ),
          ]),
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
              .having((error) => error.providerId, 'provider', 'provider-2')
              .having((error) => error.sourceId, 'source', 'same-source'),
        ),
      ),
    );
  });

  test('identical payloads deduplicate deterministically', () async {
    final result = await assembler.assemble(
      context: context,
      providers: [
        _Provider([_contribution('same', ResourceOriginKind.workspace, 'one')]),
        _Provider([_contribution('same', ResourceOriginKind.workspace, 'one')]),
      ],
    );

    expect(result.servers, hasLength(1));
    expect(result.servers.single, isA<StdioMcpServer>());
  });

  test(
    'provider completion timing does not change catalog and extra order',
    () async {
      final calls = <String>[];
      final result = await assembler.assemble(
        context: context,
        providers: [
          _Provider(
            [
              _contribution('catalog-a', ResourceOriginKind.catalog, 'a'),
              _contribution('catalog-b', ResourceOriginKind.catalog, 'b'),
            ],
            id: 'catalog',
            delay: const Duration(milliseconds: 20),
            calls: calls,
          ),
          _Provider(
            [
              _contribution('extra-a', ResourceOriginKind.managed, 'extra-a'),
              _contribution('extra-b', ResourceOriginKind.managed, 'extra-b'),
            ],
            id: 'extra',
            calls: calls,
          ),
        ],
      );

      expect(calls, ['catalog', 'extra']);
      expect(result.servers.map((server) => server.name), [
        'catalog-a',
        'catalog-b',
        'extra-a',
        'extra-b',
      ]);
    },
  );

  test('provider errors preserve provider and source metadata', () {
    expect(
      () => assembler.assemble(
        context: McpProviderContext(
          sourceId: 'source-context',
          cli: CliTool.claude,
        ),
        providers: [_Provider.failure('provider-fails')],
      ),
      throwsA(
        isA<ResourceAssemblyException>().having(
          (error) => error.diagnostics.single,
          'diagnostic',
          isA<ResourceAssemblyError>()
              .having((error) => error.providerId, 'provider', 'provider-fails')
              .having((error) => error.sourceId, 'source', 'source-context'),
        ),
      ),
    );
  });

  test('provider errors and later conflicts are aggregated', () {
    expect(
      () => assembler.assemble(
        context: context,
        providers: [
          _Provider.failure('provider-fails'),
          _Provider([
            _contribution(
              'conflict',
              ResourceOriginKind.workspace,
              'one',
              'first',
            ),
          ]),
          _Provider([
            _contribution(
              'conflict',
              ResourceOriginKind.workspace,
              'two',
              'second',
            ),
            const McpContribution(
              sourceId: '',
              server: StdioMcpServer(name: 'invalid', command: 'invalid'),
              origin: ContributionOrigin(
                providerId: 'invalid-provider',
                kind: ResourceOriginKind.workspace,
                sourceId: 'invalid-source',
              ),
            ),
          ]),
        ],
      ),
      throwsA(
        isA<ResourceAssemblyException>().having(
          (error) => error.diagnostics,
          'diagnostics',
          allOf(
            hasLength(3),
            contains(
              isA<ResourceAssemblyError>().having(
                (error) => error.providerId,
                'provider',
                'provider-fails',
              ),
            ),
            contains(
              isA<ResourceAssemblyError>()
                  .having(
                    (error) => error.errorKind,
                    'kind',
                    ResourceAssemblyErrorKind.conflict,
                  )
                  .having((error) => error.providerId, 'provider', 'second'),
            ),
            contains(
              isA<ResourceAssemblyError>()
                  .having(
                    (error) => error.providerId,
                    'provider',
                    'invalid-provider',
                  )
                  .having((error) => error.sourceId, 'source', ''),
            ),
          ),
        ),
      ),
    );
  });

  test('empty input is a safe immutable no-op', () async {
    final result = await assembler.assemble(
      context: context,
      providers: const [],
    );

    expect(result.servers, isEmpty);
    expect(result.diagnostics, isEmpty);
    expect(
      () => result.servers.add(const StdioMcpServer(name: 'x', command: 'x')),
      throwsUnsupportedError,
    );
  });
}

McpContribution _contribution(
  String name,
  ResourceOriginKind kind,
  String command, [
  String? provider,
]) => McpContribution(
  sourceId: '$name-source',
  server: StdioMcpServer(name: name, command: command),
  origin: ContributionOrigin(
    providerId: provider ?? 'provider-${kind.name}',
    kind: kind,
    sourceId: '$name-source',
  ),
);

final class _Provider implements McpContributionProvider {
  _Provider(
    this.contributions, {
    this.id = 'provider',
    this.delay = Duration.zero,
    this.calls,
  });

  _Provider.failure(this.id)
    : contributions = null,
      delay = Duration.zero,
      calls = null;

  final List<McpContribution>? contributions;
  final String id;
  final Duration delay;
  final List<String>? calls;

  @override
  String get providerId => id;

  @override
  Future<Iterable<McpContribution>> provide(McpProviderContext context) async {
    calls?.add(id);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (contributions == null) throw StateError('provider failed');
    return contributions!;
  }
}
