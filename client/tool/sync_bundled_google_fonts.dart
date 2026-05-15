// ignore_for_file: avoid_print
//
// Downloads UI + terminal fonts. Run from `client/`:
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

/// JetBrainsMono Nerd Font Mono (ligatures) — terminal + shell icons.
const _jetbrainsMonoNerdBundled = <({
  String sha256Hex,
  int byteLength,
  String assetFileName,
  String downloadUrl,
})>[
  (
    sha256Hex: 'f01031f40e48dc29e1112e6b0b0450a2c6cd097f3f35cfff05c55cb311f8034c',
    byteLength: 2470116,
    assetFileName: 'JetBrainsMonoNerdFontMono-Regular.ttf',
    downloadUrl:
        'https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFontMono-Regular.ttf',
  ),
  (
    sha256Hex: '5bdd4a873f3cd32f882d2c55545089123926e27707d5880fc9eaf84eb01b6686',
    byteLength: 2473884,
    assetFileName: 'JetBrainsMonoNerdFontMono-Bold.ttf',
    downloadUrl:
        'https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/JetBrainsMono/Ligatures/Bold/JetBrainsMonoNerdFontMono-Bold.ttf',
  ),
];

/// Optional terminal fallback ([google_fonts] Ubuntu Sans Mono descriptors).
const _ubuntuSansMonoBundled = <({
  String sha256Hex,
  int byteLength,
  String assetFileName,
})>[
  (
    sha256Hex: '44ae840b720f3e95bb69bd2449082c72d90272356c78fdbb5721b3ff5a6a97cc',
    byteLength: 111100,
    assetFileName: 'UbuntuSansMono-Regular.ttf',
  ),
  (
    sha256Hex: '5224a9bb27672470392ad5693ffe40f876408fc46ff7eea839c0b9e8ab9f144e',
    byteLength: 110672,
    assetFileName: 'UbuntuSansMono-Bold.ttf',
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

  print('Sync bundled fonts into ${clientRoot.path}\n');

  final googleFontsDir = Directory('${clientRoot.path}/google_fonts');
  final terminalFontsDir = Directory('${clientRoot.path}/assets/fonts/terminal');
  await googleFontsDir.create(recursive: true);
  await terminalFontsDir.create(recursive: true);

  print('== UI — Noto Sans SC ==');
  for (final spec in _notoSansScBundled) {
    await _syncGstaticFont(googleFontsDir, spec, force);
  }

  print('\n== Terminal — JetBrainsMono Nerd Font Mono ==');
  for (final spec in _jetbrainsMonoNerdBundled) {
    await _syncUrlFont(terminalFontsDir, spec, force);
  }

  print('\n== Terminal (fallback) — Ubuntu Sans Mono ==');
  for (final spec in _ubuntuSansMonoBundled) {
    await _syncGstaticFont(terminalFontsDir, spec, force);
  }

  print('\nDone.');
}

Future<void> _syncGstaticFont(
  Directory outDir,
  ({
    String sha256Hex,
    int byteLength,
    String assetFileName,
  }) spec,
  bool force,
) async {
  final uri = Uri.parse('https://fonts.gstatic.com/s/a/${spec.sha256Hex}.ttf');
  await _syncFontFile(
    outDir: outDir,
    assetFileName: spec.assetFileName,
    downloadUrl: uri,
    sha256Hex: spec.sha256Hex,
    byteLength: spec.byteLength,
    force: force,
  );
}

Future<void> _syncUrlFont(
  Directory outDir,
  ({
    String sha256Hex,
    int byteLength,
    String assetFileName,
    String downloadUrl,
  }) spec,
  bool force,
) async {
  await _syncFontFile(
    outDir: outDir,
    assetFileName: spec.assetFileName,
    downloadUrl: Uri.parse(spec.downloadUrl),
    sha256Hex: spec.sha256Hex,
    byteLength: spec.byteLength,
    force: force,
  );
}

Future<void> _syncFontFile({
  required Directory outDir,
  required String assetFileName,
  required Uri downloadUrl,
  required String sha256Hex,
  required int byteLength,
  required bool force,
}) async {
  final outFile = File('${outDir.path}/$assetFileName');
  if (!force &&
      await outFile.exists() &&
      await _matchesSpec(outFile, sha256Hex, byteLength)) {
    print('   OK (cached) $assetFileName');
    return;
  }

  print('   Downloading $assetFileName …');
  final response = await http.get(downloadUrl);
  if (response.statusCode != HttpStatus.ok) {
    throw StateError('HTTP ${response.statusCode} for $downloadUrl');
  }
  await _writeVerifiedBytes(
    outFile: outFile,
    bytes: response.bodyBytes,
    assetFileName: assetFileName,
    sha256Hex: sha256Hex,
    byteLength: byteLength,
  );
}

Future<void> _writeVerifiedBytes({
  required File outFile,
  required List<int> bytes,
  required String assetFileName,
  required String sha256Hex,
  required int byteLength,
}) async {
  if (bytes.length != byteLength) {
    throw StateError(
      'Wrong length for $assetFileName: expected $byteLength, got ${bytes.length}',
    );
  }
  final hash = sha256.convert(bytes).toString();
  if (hash != sha256Hex) {
    throw StateError(
      'Wrong SHA-256 for $assetFileName: expected $sha256Hex, got $hash',
    );
  }
  await outFile.writeAsBytes(bytes, flush: true);
  print('   Wrote ${outFile.path}');
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
