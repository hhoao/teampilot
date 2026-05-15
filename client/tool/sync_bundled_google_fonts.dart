// ignore_for_file: avoid_print
//
// Downloads Noto Sans SC static TTFs expected by `google_fonts` ^8.1.0 for
// asset bundling (see pubspec `google_fonts/`). Run from `client/`:
//
//   dart run tool/sync_bundled_google_fonts.dart
//
// Use `--force` to re-download even when checksums already match.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// SHA256 (hex) and byte length must match [google_fonts] package descriptors.
const _notoSansScBundled = <({
  String sha256Hex,
  int byteLength,
  String assetFileName,
})>[
  (
    sha256Hex: 'a0ecca1c67a4da5a89857703b84a44eba9fce7d7b5941bf4285e8c0a8346cf60',
    byteLength: 10540376,
    assetFileName: 'NotoSansSC-Regular.ttf',
  ),
  (
    sha256Hex: 'b85915277d672d101e3b4aa74e16e9f88d0f13e6552579e92a0d54a1291013cd',
    byteLength: 10533572,
    assetFileName: 'NotoSansSC-Medium.ttf',
  ),
  (
    sha256Hex: 'a9100a1e77488d43c4dc38cfdd3602f7169181aa8b2696ff63d8ad90308ff1e3',
    byteLength: 10530080,
    assetFileName: 'NotoSansSC-SemiBold.ttf',
  ),
  (
    sha256Hex: '2179d44af51b5fc3db254102bd9710fb50e1538754cd33349f1ae1056bf7f3c8',
    byteLength: 10530140,
    assetFileName: 'NotoSansSC-Bold.ttf',
  ),
  (
    sha256Hex: '1364bab1dd5a59a96dfe659ea03e8a120af791abb99c2b03b4366f92ed16786a',
    byteLength: 10525160,
    assetFileName: 'NotoSansSC-ExtraBold.ttf',
  ),
];

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final clientRoot = Directory.current;
  if (!File('${clientRoot.path}/pubspec.yaml').existsSync()) {
    stderr.writeln(
      'Run this script from the Flutter package root (the client/ directory).',
    );
    exitCode = 1;
    return;
  }

  final outDir = Directory('${clientRoot.path}/google_fonts');
  await outDir.create(recursive: true);

  for (final spec in _notoSansScBundled) {
    final outFile = File('${outDir.path}/${spec.assetFileName}');
    if (!force &&
        await outFile.exists() &&
        await _matchesSpec(outFile, spec.sha256Hex, spec.byteLength)) {
      print('OK (cached) ${spec.assetFileName}');
      continue;
    }

    final uri = Uri.parse(
      'https://fonts.gstatic.com/s/a/${spec.sha256Hex}.ttf',
    );
    print('Downloading ${spec.assetFileName} …');
    final response = await http.get(uri);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('HTTP ${response.statusCode} for $uri');
    }
    final bytes = response.bodyBytes;
    if (bytes.length != spec.byteLength) {
      throw StateError(
        'Wrong length for ${spec.assetFileName}: '
        'expected ${spec.byteLength}, got ${bytes.length}',
      );
    }
    final hash = sha256.convert(bytes).toString();
    if (hash != spec.sha256Hex) {
      throw StateError(
        'Wrong SHA-256 for ${spec.assetFileName}: '
        'expected ${spec.sha256Hex}, got $hash',
      );
    }
    await outFile.writeAsBytes(bytes, flush: true);
    print('Wrote ${outFile.path}');
  }
}

Future<bool> _matchesSpec(
  File file,
  String expectedSha256,
  int expectedLength,
) async {
  final len = await file.length();
  if (len != expectedLength) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == expectedSha256;
}
