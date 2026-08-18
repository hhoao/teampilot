import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/prompt_capability.dart';
import 'package:teampilot/services/resource/assemblers/prompt_assembler.dart';
import 'package:teampilot/services/resource/contribution/resource_assembly_error.dart';
import 'package:teampilot/services/resource/contribution/resource_origin.dart';
import 'package:teampilot/services/resource/providers/prompt_contribution_provider.dart';

void main() {
  final context = PromptProviderContext(cli: CliTool.claude);

  test(
    'append contributions keep provider and provider-result order',
    () async {
      final result = await PromptAssembler().assemble(
        context: context,
        providers: [
          _Provider('first', const [
            _Contribution('first-a', 'A', PromptMergeRole.append),
            _Contribution('first-b', 'B', PromptMergeRole.append),
          ]),
          _Provider('second', const [
            _Contribution('second-a', 'C', PromptMergeRole.append),
          ]),
        ],
      );

      expect(
        result.document.contributions.map((contribution) => contribution.id),
        ['first-a', 'first-b', 'second-a'],
      );
    },
  );

  test('async providers still flatten in declared order', () async {
    final result = await PromptAssembler().assemble(
      context: context,
      providers: [
        _Provider('slow', const [
          _Contribution('slow', 'slow', PromptMergeRole.append),
        ], delay: const Duration(milliseconds: 30)),
        _Provider('fast', const [
          _Contribution('fast', 'fast', PromptMergeRole.append),
        ], delay: const Duration(milliseconds: 1)),
      ],
    );

    expect(
      result.document.contributions.map((contribution) => contribution.id),
      ['slow', 'fast'],
    );
  });

  test(
    'same-layer replace uses the later contribution and reports conflict',
    () async {
      final result = await PromptAssembler().assemble(
        context: context,
        providers: [
          _Provider('one', const [
            _Contribution('same', 'one', PromptMergeRole.replace),
          ], sourceId: 'one-source'),
          _Provider('two', const [
            _Contribution('same', 'two', PromptMergeRole.replace),
          ], sourceId: 'two-source'),
        ],
      );

      expect(result.document.sections.single.content, 'two');
      expect(result.diagnostics, hasLength(1));
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.providerId, 'two');
      expect(diagnostic.sourceId, 'two-source');
      expect(diagnostic.message, contains('one'));
      expect(diagnostic.message, contains('one-source'));
      expect(diagnostic.message, contains('two'));
      expect(diagnostic.message, contains('two-source'));
    },
  );

  test('higher-layer replace supersedes lower layer with a warning', () async {
    final result = await PromptAssembler().assemble(
      context: context,
      providers: [
        _Provider('global', const [
          _Contribution(
            'role',
            'global role',
            PromptMergeRole.replace,
            scope: PromptScope.global,
          ),
        ]),
        _Provider('workspace', const [
          _Contribution(
            'role',
            'workspace role',
            PromptMergeRole.replace,
            scope: PromptScope.workspace,
          ),
        ]),
      ],
    );

    expect(result.document.sections.map((section) => section.content), [
      'workspace role',
      'global role',
    ]);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.providerId, 'global');
    expect(result.warnings.single.sourceId, 'role');
  });

  test(
    'same-layer sections merge and report both contribution origins',
    () async {
      final result = await PromptAssembler().assemble(
        context: context,
        providers: [
          _Provider('section-one', const [
            _Contribution('shared', 'one', PromptMergeRole.section),
          ], sourceId: 'source-one'),
          _Provider('section-two', const [
            _Contribution('shared', 'two', PromptMergeRole.section),
          ], sourceId: 'source-two'),
        ],
      );

      expect(result.document.sections.single.content, 'one\n\ntwo');
      expect(result.diagnostics, hasLength(1));
      final diagnostic = result.diagnostics.single;
      expect(diagnostic.providerId, 'section-two');
      expect(diagnostic.sourceId, 'source-two');
      expect(diagnostic.message, contains('section-one'));
      expect(diagnostic.message, contains('source-one'));
      expect(diagnostic.message, contains('section-two'));
      expect(diagnostic.message, contains('source-two'));
    },
  );

  test('lower-layer sections remain independent append content', () async {
    final result = await PromptAssembler().assemble(
      context: context,
      providers: [
        _Provider('high', const [
          _Contribution(
            'shared',
            'high section',
            PromptMergeRole.section,
            scope: PromptScope.workspace,
          ),
        ]),
        _Provider('low', const [
          _Contribution(
            'shared',
            'low section',
            PromptMergeRole.section,
            scope: PromptScope.global,
          ),
        ]),
      ],
    );

    expect(result.document.sections.map((section) => section.content), [
      'high section',
      'low section',
    ]);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.providerId, 'low');
  });

  test(
    'sections are grouped by id while preserving stable section order',
    () async {
      final result = await PromptAssembler().assemble(
        context: context,
        providers: [
          _Provider('sections', const [
            _Contribution('z', 'Z1', PromptMergeRole.section),
            _Contribution('a', 'A1', PromptMergeRole.section),
            _Contribution('z', 'Z2', PromptMergeRole.section),
          ]),
        ],
      );

      expect(result.document.sections.map((section) => section.content), [
        'Z1\n\nZ2',
        'A1',
      ]);
    },
  );

  test('empty providers produce an empty document and diagnostics', () async {
    final result = await PromptAssembler().assemble(
      context: context,
      providers: const [],
    );

    expect(result.document.contributions, isEmpty);
    expect(result.diagnostics, isEmpty);
  });

  test(
    'provider failure carries provider, source, CLI, and resource metadata',
    () async {
      final future = PromptAssembler().assemble(
        context: context,
        providers: [_Provider('broken', const [], error: StateError('boom'))],
      );

      await expectLater(
        future,
        throwsA(
          isA<ResourceAssemblyException>().having(
            (exception) => exception.diagnostics.single,
            'diagnostic',
            isA<ResourceAssemblyError>()
                .having(
                  (diagnostic) => diagnostic.providerId,
                  'providerId',
                  'broken',
                )
                .having(
                  (diagnostic) => diagnostic.sourceId,
                  'sourceId',
                  'broken',
                )
                .having((diagnostic) => diagnostic.cli, 'cli', CliTool.claude)
                .having(
                  (diagnostic) => diagnostic.resourceKind,
                  'resourceKind',
                  ResourceContributionKind.prompt,
                ),
          ),
        ),
      );
    },
  );

  test(
    'iterable iteration failure is wrapped with provider metadata',
    () async {
      final future = PromptAssembler().assemble(
        context: PromptProviderContext(
          cli: CliTool.claude,
          sourceId: 'iter-source',
        ),
        providers: const [_IteratingFailureProvider()],
      );

      await expectLater(
        future,
        throwsA(
          isA<ResourceAssemblyException>().having(
            (exception) => exception.diagnostics.single,
            'diagnostic',
            isA<ResourceAssemblyError>()
                .having(
                  (diagnostic) => diagnostic.providerId,
                  'providerId',
                  'iterating-provider',
                )
                .having(
                  (diagnostic) => diagnostic.sourceId,
                  'sourceId',
                  'iter-source',
                )
                .having((diagnostic) => diagnostic.cli, 'cli', CliTool.claude)
                .having(
                  (diagnostic) => diagnostic.resourceKind,
                  'resourceKind',
                  ResourceContributionKind.prompt,
                ),
          ),
        ),
      );
    },
  );

  test('empty contribution ids are rejected', () async {
    final future = PromptAssembler().assemble(
      context: context,
      providers: [
        _Provider('invalid', const [
          _Contribution('', 'missing id', PromptMergeRole.append),
        ]),
      ],
    );

    await expectLater(future, throwsA(isA<ResourceAssemblyException>()));
  });
}

final class _Provider implements PromptContributionProvider {
  _Provider(
    this.providerId,
    this.contributions, {
    this.delay,
    this.error,
    this.sourceId,
  });

  @override
  final String providerId;

  final List<_Contribution> contributions;
  final Duration? delay;
  final Object? error;
  final String? sourceId;

  @override
  Future<Iterable<PromptContribution>> provide(
    PromptProviderContext context,
  ) async {
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return contributions.map(
      (contribution) => PromptContribution(
        id: contribution.id,
        title: contribution.title,
        content: contribution.content,
        scope: contribution.scope,
        mergeRole: contribution.mergeRole,
        origin: ContributionOrigin(
          providerId: providerId,
          kind: ResourceOriginKind.cliBuiltIn,
          sourceId: sourceId ?? contribution.id,
        ),
      ),
    );
  }
}

final class _IteratingFailureProvider implements PromptContributionProvider {
  const _IteratingFailureProvider();

  @override
  String get providerId => 'iterating-provider';

  @override
  Iterable<PromptContribution> provide(PromptProviderContext context) sync* {
    yield const PromptContribution(
      id: 'before-failure',
      title: 'Before failure',
      content: 'before failure',
      mergeRole: PromptMergeRole.append,
      origin: ContributionOrigin(
        providerId: 'iterating-provider',
        kind: ResourceOriginKind.workspace,
        sourceId: 'iter-source',
      ),
    );
    throw StateError('iteration boom');
  }
}

class _Contribution {
  const _Contribution(
    this.id,
    this.content,
    this.mergeRole, {
    this.scope = PromptScope.cli,
  });

  final String id;
  String get title => id;
  final String content;
  final PromptMergeRole mergeRole;
  final PromptScope scope;
}
