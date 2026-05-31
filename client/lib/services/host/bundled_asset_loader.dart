import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Loads a `pubspec.yaml` `flutter.assets` entry as UTF-8 text.
///
/// Uses [rootBundle] first. On desktop, falls back to the on-disk
/// `data/flutter_assets` tree (and debug `build/flutter_assets` / source
/// paths) when the bundle is missing or empty — e.g. after adding assets
/// without a full restart/rebuild.
Future<String> loadBundledAssetString(String assetKey) async {
  final normalized = assetKey.startsWith('/')
      ? assetKey.substring(1)
      : assetKey;

  try {
    final fromBundle = await rootBundle.loadString(normalized);
    if (fromBundle.isNotEmpty) return fromBundle;
  } on Object {
    // Fall through to on-disk layout.
  }

  final fromDisk = await _readFlutterAssetFromDisk(normalized);
  if (fromDisk != null && fromDisk.isNotEmpty) return fromDisk;

  throw FlutterError(
    'Unable to load asset: "$normalized". '
    'The asset does not exist or has empty data.',
  );
}

Future<String?> _readFlutterAssetFromDisk(String assetKey) async {
  if (kIsWeb) return null;

  for (final base in _desktopAssetRoots()) {
    final file = File(p.join(base, assetKey));
    if (!file.existsSync()) continue;
    final text = await file.readAsString();
    if (text.isNotEmpty) return text;
  }
  return null;
}

Iterable<String> _desktopAssetRoots() sync* {
  if (kIsWeb) return;

  final exeDir = File(Platform.resolvedExecutable).parent.path;
  yield p.join(exeDir, 'data', 'flutter_assets');

  if (!kDebugMode) return;

  final cwd = Directory.current.path;
  yield p.join(cwd, 'build', 'flutter_assets');
  yield p.join(cwd, 'build', 'unit_test_assets');

  final clientRoot = p.basename(cwd) == 'client' ? cwd : p.join(cwd, 'client');
  yield p.join(clientRoot, 'build', 'flutter_assets');
  yield p.join(clientRoot, 'build', 'unit_test_assets');
  // Source tree when assets were added but the app was not fully rebuilt.
  yield clientRoot;
}
