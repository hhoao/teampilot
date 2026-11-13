import 'dart:io';

/// Concatenated source of the app composition root and its bootstrap modules.
///
/// Source-pin tests assert on wiring that is not behavior-testable. Reading the
/// whole `lib/app/` tree keeps those pins valid when wiring moves between
/// files during the bootstrap split.
String readAppBootstrapSource() {
  final files =
      Directory('lib/app')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files.map((file) => file.readAsStringSync()).join('\n');
}
