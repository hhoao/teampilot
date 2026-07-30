import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/home_storage_invalidator.dart';
import 'package:teampilot/widgets/ssh/home_ssh_profile_binder.dart';

void main() {
  late Directory temp;
  late SshProfileRepository repository;
  late SshProfileCubit cubit;
  late List<String> actions;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('home_ssh_binder_');
    repository = SshProfileRepository(rootDir: temp.path);
    cubit = SshProfileCubit(
      profileRepository: repository,
      credentialStore: InMemorySshCredentialStore(),
    );
    actions = <String>[];
  });

  tearDown(() async {
    await cubit.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> pumpBinder(WidgetTester tester, {required String homeId}) async {
    final invalidator = HomeStorageInvalidator(
      homeTargetId: () => homeId,
      reinstallAndReload: () async => actions.add('reinstall'),
      switchHome: (id) async => actions.add('switch:$id'),
    );
    await tester.pumpWidget(
      RepositoryProvider<HomeStorageInvalidator>.value(
        value: invalidator,
        child: BlocProvider<SshProfileCubit>.value(
          value: cubit,
          child: const HomeSshProfileBinder(child: SizedBox()),
        ),
      ),
    );
    await tester.pump(); // prime post-frame baseline
  }

  testWidgets('unrelated profile save does not invalidate home', (tester) async {
    await tester.runAsync(() async {
      await repository.save(
        const SshProfile(
          id: 'p1',
          name: 'Home',
          host: 'home.example.com',
          username: 'alice',
        ),
      );
      await cubit.load();
    });
    await pumpBinder(tester, homeId: 'ssh:p1');
    actions.clear();

    await tester.runAsync(
      () => cubit.saveProfile(
        const SshProfile(
          id: 'p2',
          name: 'Other',
          host: 'other.example.com',
          username: 'bob',
        ),
      ),
    );
    await tester.pump();

    expect(actions, isEmpty);
  });

  testWidgets('home host change reinstalls', (tester) async {
    await tester.runAsync(() async {
      await repository.save(
        const SshProfile(
          id: 'p1',
          name: 'Home',
          host: 'home.example.com',
          username: 'alice',
        ),
      );
      await cubit.load();
    });
    await pumpBinder(tester, homeId: 'ssh:p1');
    actions.clear();

    await tester.runAsync(
      () => cubit.saveProfile(
        const SshProfile(
          id: 'p1',
          name: 'Home',
          host: 'new.example.com',
          username: 'alice',
        ),
      ),
    );
    await tester.pump();

    expect(actions, ['reinstall']);
  });
}
