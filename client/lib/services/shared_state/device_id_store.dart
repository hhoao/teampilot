import 'package:uuid/uuid.dart';

import '../io/filesystem.dart';

/// Reads (or creates once) the stable device id used by shared-state stamps.
///
/// The file lives in the device plane, not the home plane: it identifies the
/// replica, so it must not travel to another device through the shared home.
final class DeviceIdStore {
  DeviceIdStore({
    required Filesystem fs,
    required String path,
    String Function()? generate,
  }) : _fs = fs,
       _path = path,
       _generate = generate ?? _defaultGenerate;

  static const _uuid = Uuid();
  static final _valid = RegExp(r'^[A-Za-z0-9_.:-]{8,128}$');

  final Filesystem _fs;
  final String _path;
  final String Function() _generate;

  static String _defaultGenerate() => _uuid.v4();

  Future<String> loadOrCreate() async {
    final existing = (await _fs.readString(_path))?.trim() ?? '';
    if (_valid.hasMatch(existing)) return existing;

    final id = _generate().trim();
    if (!_valid.hasMatch(id)) {
      throw StateError('generated device id is not valid: $id');
    }
    final dir = _fs.pathContext.dirname(_path);
    if (dir.isNotEmpty && dir != '.') {
      await _fs.ensureDir(dir);
    }
    await _fs.atomicWrite(_path, id);
    return id;
  }
}
