// ignore_for_file: avoid_print
//
// Regenerates launcher icons (Android, Windows, macOS) and syncs the Linux
// bundle icon. Run from `client/`:
//
//   dart run tool/sync_app_icons.dart
//
// Source artwork: `assets/icons/icon_bg.png` (launcher icon with background;
// prefer 1024×1024). Transparent-only mark: `assets/icons/icon.png`.

import 'dart:io';

const _sourceIcon = 'assets/icons/icon_bg.png';
const _linuxBundleIcon = 'linux/runner/resources/app_icon.png';

Future<void> main() async {
  final clientRoot = Directory.current;
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run from the client/ directory (pubspec.yaml not found).');
    exit(1);
  }

  final source = File(_sourceIcon);
  if (!source.existsSync()) {
    stderr.writeln('Missing $_sourceIcon — add or export the app icon first.');
    exit(1);
  }

  print('Running flutter_launcher_icons…');
  final gen = await Process.run(
    'dart',
    ['run', 'flutter_launcher_icons'],
    workingDirectory: clientRoot.path,
  );
  stdout.write(gen.stdout);
  stderr.write(gen.stderr);
  if (gen.exitCode != 0) {
    exit(gen.exitCode);
  }

  final linuxDest = File(_linuxBundleIcon);
  await linuxDest.parent.create(recursive: true);
  await source.copy(linuxDest.path);
  print('Synced $_sourceIcon → $_linuxBundleIcon');
  print('Done.');
}
