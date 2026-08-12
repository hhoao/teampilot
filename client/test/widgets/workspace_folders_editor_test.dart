import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import 'package:teampilot/widgets/workspace_folders_editor.dart';

import '../support/in_memory_filesystem.dart';

Future<HomeTargetController> _controllerWithSshProfiles(
  List<SshProfile> profiles,
) async {
  const root = '/tp-test-editor';
  final sshRepo = SshProfileRepository(rootDir: root, fs: InMemoryFilesystem());
  for (final p in profiles) {
    await sshRepo.save(p);
  }
  return HomeTargetController(
    registry: RuntimeTargetRegistry(
      repo: TargetsRepository(rootDir: root, fs: InMemoryFilesystem()),
      sshProfileRepo: sshRepo,
      isWindows: false,
      isAndroid: false,
    ),
    current: RuntimeTarget.local,
    switchTo: (_) async {},
  );
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required HomeTargetController controller,
  required List<WorkspaceFolder> folders,
  bool lockTargets = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepositoryProvider<HomeTargetController>.value(
        value: controller,
        child: Scaffold(
          body: WorkspaceFoldersEditor(
            folders: folders,
            lockTargets: lockTargets,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

void main() {
  final serverA = SshProfile(
    id: 'p1',
    name: 'Server A',
    host: '10.0.0.1',
    username: 'root',
  );
  final serverB = SshProfile(
    id: 'p2',
    name: 'Server B',
    host: '10.0.0.2',
    username: 'root',
  );

  testWidgets(
    'locked editor hides Change and Add-on-another-machine',
    (tester) async {
      final controller = await _controllerWithSshProfiles([serverA, serverB]);
      await _pumpEditor(
        tester,
        controller: controller,
        folders: const [WorkspaceFolder(path: '/proj')],
        lockTargets: true,
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.workspaceFoldersChangeTarget),
        findsNothing,
      );
      expect(
        find.text(l10n.workspaceFoldersAddOnAnotherMachine),
        findsNothing,
      );
    },
  );

  testWidgets(
    'unlocked editor shows Change; group picker lists all machines',
    (tester) async {
      final controller = await _controllerWithSshProfiles([serverA, serverB]);
      await _pumpEditor(
        tester,
        controller: controller,
        folders: const [WorkspaceFolder(path: '/proj')],
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.workspaceFoldersChangeTarget), findsOneWidget);

      await tester.tap(find.text(l10n.workspaceFoldersChangeTarget));
      await tester.pumpAndSettle();
      expect(find.text(l10n.workspaceFoldersPickTarget), findsOneWidget);
      final dialog = find.byType(SimpleDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('This device')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Server A')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Server B')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Add on another machine picker lists unused machines only',
    (tester) async {
      final controller = await _controllerWithSshProfiles([serverA, serverB]);
      await _pumpEditor(
        tester,
        controller: controller,
        folders: const [WorkspaceFolder(path: '/proj')],
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.workspaceFoldersAddOnAnotherMachine));
      await tester.pumpAndSettle();
      final dialog = find.byType(SimpleDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Server A')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('Server B')),
        findsOneWidget,
      );
      // 'This device' is already used by /proj, so it is not a candidate.
      expect(
        find.descendant(of: dialog, matching: find.text('This device')),
        findsNothing,
      );
    },
  );

  testWidgets('mixed workspace is not locked', (tester) async {
    final controller = await _controllerWithSshProfiles([serverA, serverB]);
    await _pumpEditor(
      tester,
      controller: controller,
      folders: const [
        WorkspaceFolder(path: '/local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ],
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.workspaceFoldersChangeTarget), findsNWidgets(2));
    expect(
      find.text(l10n.workspaceFoldersAddOnAnotherMachine),
      findsOneWidget,
    );
  });
}
