import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/remote_download_catalog_cubit.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/remote_download/remote_download_settings_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  test('restoreDefaults clears mirror from persisted settings', () async {
    final rootDir = await Directory.systemTemp.createTemp('download_src_ui_');
    addTearDown(() async {
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    });
    final store = RemoteDownloadSettingsStore(
      rootDir: rootDir.path,
      fs: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(rootDir.path),
      ),
    );
    await store.save(
      const RemoteDownloadSettings(mirrorBaseUrl: 'https://mirror.example'),
    );

    final cubit = RemoteDownloadCatalogCubit(store: store);
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.restoreDefaults();

    expect(cubit.state.mirrorBaseUrl, isNull);
    expect(await store.load(), isNull);
  });
}
