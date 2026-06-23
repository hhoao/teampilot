import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/plugin/plugin_install_service.dart';
import 'package:teampilot/services/plugin/plugin_manifest_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('plugin-install-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('installFromZip extracts plugin and persists Plugin record', () async {
    final archive = Archive();
    final manifest = '{"name":"my-plugin","version":"1.0.0","description":"hi"}';
    archive.addFile(ArchiveFile(
      '.claude-plugin/plugin.json',
      manifest.length,
      utf8.encode(manifest),
    ));
    final zipBytes = ZipEncoder().encode(archive);
    final zipFile = File(p.join(tmp.path, 'in.zip'))..writeAsBytesSync(zipBytes);

    final svc = PluginInstallService(manifestService: PluginManifestService());
    final installed = await svc.installFromZip(zipFile);

    expect(installed.name, 'my-plugin');
    expect(installed.id, startsWith('local/'));
    expect(installed.marketplaceOwner, isNull);
    final installedDir =
        Directory(p.join(tmp.path, 'plugins', 'installed', installed.directory));
    expect(installedDir.existsSync(), isTrue);
    expect(
      File(p.join(installedDir.path, '.plugin', 'plugin.json')).existsSync(),
      isTrue,
    );

    final jsonFile = File(p.join(tmp.path, 'plugins', 'plugins.json'));
    expect(jsonFile.existsSync(), isTrue);
  });

  test('uninstall removes directory and updates plugins.json', () async {
    final svc = PluginInstallService(manifestService: PluginManifestService());
    final installed = await _installMinimal(svc, tmp);
    final dir =
        Directory(p.join(tmp.path, 'plugins', 'installed', installed.directory));
    expect(dir.existsSync(), isTrue);

    await svc.uninstall(installed);
    expect(dir.existsSync(), isFalse);
    final backups = Directory(p.join(tmp.path, 'plugins', 'backups'));
    expect(backups.existsSync(), isTrue);
    expect(backups.listSync(), isNotEmpty);
  });
}

Future<Plugin> _installMinimal(PluginInstallService svc, Directory tmp) async {
  final src = Directory(p.join(tmp.path, 'src-plugin'))..createSync();
  Directory(p.join(src.path, '.claude-plugin')).createSync();
  File(p.join(src.path, '.claude-plugin', 'plugin.json'))
      .writeAsStringSync('{"name":"foo","version":"0.1.0"}');
  return svc.installFromDirectory(src);
}
