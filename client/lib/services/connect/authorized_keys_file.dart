typedef AuthorizedKeysRead = Future<String?> Function(String path);
typedef AuthorizedKeysWrite = Future<void> Function(String path, String value);
typedef AuthorizedKeysChmod =
    Future<void> Function(String path, {required int mode});

class AuthorizedKeysFile {
  AuthorizedKeysFile({
    required this.path,
    required AuthorizedKeysRead read,
    required AuthorizedKeysWrite write,
    required AuthorizedKeysChmod chmod,
  }) : _read = read,
       _write = write,
       _chmod = chmod;

  final String path;
  final AuthorizedKeysRead _read;
  final AuthorizedKeysWrite _write;
  final AuthorizedKeysChmod _chmod;

  Future<void> upsertDevice({
    required String publicKey,
    required String deviceId,
    required String deviceName,
  }) async {
    _validateDeviceId(deviceId);
    final lines = await _readLines();
    lines.removeWhere((line) => _deviceIdFor(line) == deviceId);
    final name = deviceName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    lines.add('$publicKey teampilot-pair device=$deviceId name=$name');
    await _writeLines(lines);
  }

  Future<void> revokeDevice(String deviceId) async {
    _validateDeviceId(deviceId);
    final lines = await _readLines();
    lines.removeWhere((line) => _deviceIdFor(line) == deviceId);
    await _writeLines(lines);
  }

  Future<List<({String deviceId, String name})>> listDevices() async {
    final devices = <({String deviceId, String name})>[];
    for (final line in await _readLines()) {
      final match = RegExp(
        r'\bteampilot-pair\s+device=([^\s]+)\s+name=([^\s]+)',
      ).firstMatch(line);
      if (match != null) {
        devices.add((deviceId: match.group(1)!, name: match.group(2)!));
      }
    }
    return devices;
  }

  Future<List<String>> _readLines() async {
    final contents = await _read(path) ?? '';
    return contents
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: true);
  }

  Future<void> _writeLines(List<String> lines) async {
    final contents = lines.isEmpty ? '' : '${lines.join('\n')}\n';
    await _write(path, contents);
    await _chmod(path, mode: 384);
  }

  String? _deviceIdFor(String line) {
    return RegExp(
      r'\bteampilot-pair\s+device=([^\s]+)',
    ).firstMatch(line)?.group(1);
  }

  void _validateDeviceId(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'deviceId', 'must be a safe token');
    }
  }
}
