import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/pages/config/runtime_target_picker.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late HomeTargetController controller;
  late String currentId;
  final selected = <String>[];

  Future<void> setup({
    required String home,
    List<String> sshIds = const [],
  }) async {
    final fs = InMemoryFilesystem();
    const root = '/tp';
    final sshRepo = SshProfileRepository(rootDir: root, fs: fs);
    for (final id in sshIds) {
      await sshRepo.save(
        SshProfile(id: id, name: 'box-$id', host: 'h', username: 'u'),
      );
    }
    final registry = RuntimeTargetRegistry(
      repo: TargetsRepository(rootDir: root, fs: fs),
      sshProfileRepo: sshRepo,
      isWindows: false,
      isAndroid: sshIds.isNotEmpty,
    );
    currentId = home;
    selected.clear();
    controller = HomeTargetController(
      registry: registry,
      current: () => RuntimeTarget(
        id: currentId,
        label: currentId,
        kind: runtimeKindOfId(currentId),
      ),
      switchTo: (id) async {
        selected.add(id);
        currentId = id;
      },
    );
  }

  Widget host({bool isAndroid = false, bool isWindows = false}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: RepositoryProvider<HomeTargetController>.value(
        value: controller,
        child: RuntimeTargetPicker(
          isAndroidOverride: isAndroid,
          isWindowsOverride: isWindows,
        ),
      ),
    ),
  );

  testWidgets('desktop non-Windows shows only local', (tester) async {
    await setup(home: 'local');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('local'), findsWidgets);
    expect(find.textContaining('ssh:'), findsNothing);
  });

  testWidgets('Android lists ssh targets and selecting one switches home',
      (tester) async {
    await setup(home: 'ssh:p1', sshIds: ['p1', 'p2']);
    await tester.pumpWidget(host(isAndroid: true));
    await tester.pumpAndSettle();
    // local is filtered out on Android
    expect(find.text('box-p2'), findsOneWidget);
    await tester.tap(find.text('box-p2'));
    await tester.pumpAndSettle();
    expect(selected, ['ssh:p2']);
  });
}
