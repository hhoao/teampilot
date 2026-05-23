import 'dart:io';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin_install_service.dart';
import 'package:teampilot/services/plugin_manifest_service.dart';
import 'package:teampilot/services/plugin_repo_service.dart';
import 'package:teampilot/services/runtime_storage_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-cubit-');
    final paths = AppPaths(tmp.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    RuntimeStorageContext.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('load() populates installed + marketplaces', () async {
    final cubit = PluginCubit(
      repository: PluginRepository(),
      installService: PluginInstallService(manifestService: PluginManifestService()),
      repoService: PluginRepoService(),
    );
    await cubit.load();
    expect(cubit.state.status, PluginLoadStatus.ready);
    expect(cubit.state.marketplaces, isNotEmpty);
    expect(cubit.state.installed, isEmpty);
  });
}
