import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

class PluginFetchService {
  Future<void> extractZip(File zip, Directory destination) async {
    final bytes = await zip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    if (!destination.existsSync()) destination.createSync(recursive: true);
    for (final entry in archive) {
      final out = p.join(destination.path, entry.name);
      if (entry.isFile) {
        File(out)
          ..createSync(recursive: true)
          ..writeAsBytesSync(entry.content as List<int>);
      } else {
        Directory(out).createSync(recursive: true);
      }
    }
  }

  Future<void> copyDirectory(Directory from, Directory to) async {
    if (!to.existsSync()) to.createSync(recursive: true);
    for (final entry in from.listSync(recursive: true)) {
      final rel = p.relative(entry.path, from: from.path);
      final dest = p.join(to.path, rel);
      if (entry is File) {
        File(dest)..createSync(recursive: true)..writeAsBytesSync(entry.readAsBytesSync());
      } else if (entry is Directory) {
        Directory(dest).createSync(recursive: true);
      }
    }
  }
}
