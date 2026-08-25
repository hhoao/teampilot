import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/pages/llm_config/llm_config_helpers.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';

void main() {
  late Directory temp;
  late AppProviderCubit cubit;
  late AppProviderRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('llm_config_helpers_');
    repository = AppProviderRepository(basePath: temp.path);
    cubit = AppProviderCubit(repository: repository, basePath: temp.path);
  });

  tearDown(() async {
    await cubit.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  const officialRow = AppProviderConfig(
    id: 'openai-official',
    cli: CliTool.codex,
    name: 'OpenAI Official',
    category: AppProviderCategory.official,
    isOfficial: true,
  );

  Future<void> seed({List<AppProviderConfig> extra = const []}) async {
    await repository.saveProviders(CliTool.codex, [officialRow, ...extra]);
    await cubit.load();
  }

  Future<String?> saveDraft(
    WidgetTester tester,
    AppProviderConfig draft,
  ) async {
    String? savedId;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  savedId = await saveNewAppProvider(context, draft);
                },
                child: const Text('save'),
              ),
            ),
          ),
        ),
      ),
    );
    // Real disk IO must run on the real event loop.
    await tester.runAsync(() async {
      await tester.tap(find.text('save'));
      for (var i = 0; i < 40 && savedId == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    return savedId;
  }

  testWidgets(
    'keeps form-assigned duplicate official id instead of re-bumping',
    (tester) async {
      // Row + credential placeholder a form-side login already created.
      const placeholder = AppProviderConfig(
        id: 'openai-official-2',
        cli: CliTool.codex,
        name: 'OpenAI Official',
        category: AppProviderCategory.official,
        isOfficial: true,
      );
      await tester.runAsync(() => seed(extra: [placeholder]));

      final savedId = await saveDraft(tester, placeholder);
      expect(savedId, 'openai-official-2');
      expect(
        cubit.state.providersFor(CliTool.codex).map((p) => p.id),
        containsAll(['openai-official', 'openai-official-2']),
      );
    },
  );

  testWidgets('bumps id when base id belongs to a different identity', (
    tester,
  ) async {
    await tester.runAsync(() => seed());

    // Custom provider typed with the official preset name must not replace
    // the official row.
    const customDraft = AppProviderConfig(
      id: 'openai-official',
      cli: CliTool.codex,
      name: 'OpenAI Official',
      category: AppProviderCategory.custom,
    );

    final savedId = await saveDraft(tester, customDraft);
    expect(savedId, 'openai-official-2');
    expect(
      cubit.state.providersFor(CliTool.codex).map((p) => p.id),
      containsAll(['openai-official', 'openai-official-2']),
    );
    final official = cubit.state
        .providersFor(CliTool.codex)
        .firstWhere((p) => p.id == 'openai-official');
    expect(official.isOfficial, isTrue);
  });
}