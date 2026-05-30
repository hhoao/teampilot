import 'dart:io';

import 'package:flutter_alacritty/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _rustCrateDir = p.join(
  'packages',
  'flutter_alacritty',
  'packages',
  'rust_lib_flutter_alacritty',
  'rust',
);

String _rustLibFileName() {
  if (Platform.isWindows) return 'rust_lib_flutter_alacritty.dll';
  if (Platform.isMacOS) return 'librust_lib_flutter_alacritty.dylib';
  return 'librust_lib_flutter_alacritty.so';
}

/// Loads (or builds) the flutter_alacritty native library for widget/unit tests.
Future<void> initRustLibForTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final name = _rustLibFileName();
  final built = p.join(_rustCrateDir, 'target', 'debug', name);
  if (!File(built).existsSync()) {
    final result = await Process.run(
      'cargo',
      ['build'],
      workingDirectory: _rustCrateDir,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'cargo build failed in $_rustCrateDir: ${result.stderr}',
      );
    }
  }
  if (!File(built).existsSync()) {
    throw StateError('Rust lib not found at $built');
  }
  await RustLib.init(
    externalLibrary: ExternalLibrary.open(File(built).absolute.path),
  );
}
