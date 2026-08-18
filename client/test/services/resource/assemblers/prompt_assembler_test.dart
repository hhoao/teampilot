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

  test('same-layer replace contributions throw a conflict', () async {
    final future = PromptAssembler().assemble(
      context: context,
      providers: [
        _Provider('one', const [
          _Contribution('same', 'one', PromptMergeRole.replace),
        ]),
        _Provider('two', const [
          _Contribution('same', 'two', PromptMergeRole.replace),
        ]),
      ],
    );

    await expectLater(
      future,
      throwsA(
        isA<ResourceAssemblyException>().having(
          (exception) => exception.diagnostics.single.message,
          'message',
          contains('same'),
        ),
      ),
    );
  });

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

    expect(result.document.contributions.single.content, 'workspace role');
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.sourceId, 'role');
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
  _Provider(this.providerId, this.contributions, {this.delay, this.error});

  @override
  final String providerId;

  final List<_Contribution> contributions;
  final Duration? delay;
  final Object? error;

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
          sourceId: contribution.id,
        ),
      ),
    );
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
