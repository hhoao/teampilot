import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/widgets/git/git_source_control_panel.dart';

class _RepoGitStub extends GitService {
  _RepoGitStub()
    : super(
        runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async =>
            ProcessResult(0, 0, '/usr/bin/git\n', ''),
      );

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => const GitRepoStatus(
    isRepository: true,
    staged: [
      GitFileChange(path: 'a.txt', kind: GitChangeKind.modified, staged: true),
    ],
    unstaged: [],
    branch: 'main',
  );

  @override
  Future<List<String>> branches(String dir) async => const ['main'];
}

void main() {
  setUp(() {
    GitService.debugOverrideFactory = _RepoGitStub.new;
  });

  tearDown(() {
    GitService.debugOverrideFactory = null;
  });

  testWidgets('shows a generate-commit action button', (tester) async {
    final aiSettingsCubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: aiSettingsCubit,
          child: const Scaffold(
            body: GitSourceControlPanel(roots: ['/repo']),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('git-generate-commit-button')),
      findsOneWidget,
    );

    await aiSettingsCubit.close();
  });
}
