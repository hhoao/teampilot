import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';

void main() {
  late Directory temp;
  late AppProviderCubit cubit;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('app_provider_cubit_');
    cubit = AppProviderCubit(
      repository: AppProviderRepository(
        providersFile: File(p.join(temp.path, 'providers.json')),
      ),
    );
  });

  tearDown(() async {
    await cubit.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test(
    'deleteProvider selects the next provider when current is removed',
    () async {
      await cubit.upsertProvider(const AppProviderConfig(id: 'a', name: 'A'));
      await cubit.upsertProvider(const AppProviderConfig(id: 'b', name: 'B'));
      cubit.selectProvider('a');

      await cubit.deleteProvider('a');

      expect(cubit.state.selectedId, 'b');
      expect(cubit.state.providers.map((p) => p.id), ['b']);
    },
  );
}
