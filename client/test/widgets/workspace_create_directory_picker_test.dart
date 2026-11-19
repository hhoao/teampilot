import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import 'package:teampilot/widgets/workspace_create_directory_picker.dart';

import '../support/in_memory_filesystem.dart';

Future<HomeTargetController> _controllerWithSshProfile() async {
  const root = '/tp-test-create-picker';
  final sshRepo = SshProfileRepository(
    rootDir: root,
    fs: InMemoryFilesystem(),
    storage: fakeHomeStorage(),
  );
  await sshRepo.save(
    const SshProfile(
      id: 'p1',
      name: 'Very long server label for remote work',
      host: '10.0.0.1',
      username: 'root',
    ),
  );
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

Future<void> _pumpPicker(WidgetTester tester, {required double width}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final controller = await _controllerWithSshProfile();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
      home: TpTheme(
        data: TpThemeData.fromColorScheme(
          ColorScheme.fromSeed(seedColor: Colors.blue),
          scale: 1,
        ),
        child: RepositoryProvider<HomeTargetController>.value(
          value: controller,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: WorkspaceCreateDirectoryPicker(
                  targetId: 'ssh:p1',
                  onTargetChanged: (_) {},
                  folders: const [WorkspaceFolder(path: '/tmp/x')],
                  onFoldersChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('narrow dialog width stacks controls without overflow', (
    tester,
  ) async {
    await _pumpPicker(tester, width: 341.9);

    expect(tester.takeException(), isNull);
    expect(find.byType(TpCompactSelect<String>), findsOneWidget);
    expect(find.text('选择文件夹'), findsOneWidget);
  });

  testWidgets('wide layout keeps label, select and button on one row', (
    tester,
  ) async {
    await _pumpPicker(tester, width: 520);

    expect(tester.takeException(), isNull);
    expect(find.byType(TpCompactSelect<String>), findsOneWidget);
    expect(find.text('工作区目录'), findsOneWidget);
  });
}
