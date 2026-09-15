import 'dart:convert';

import '../io/filesystem.dart';

typedef AuthorizedKeysChmod = Future<void> Function(String path);

class AuthorizedKeysFile {
  AuthorizedKeysFile({
    required this.fs,
    required this.homePath,
    AuthorizedKeysChmod? chmod600,
  }) : _chmod600 = chmod600;

  final Filesystem fs;
  final String homePath;
  final AuthorizedKeysChmod? _chmod600;

  String get path => '$homePath/.ssh/authorized_keys';

  Future<void> authorize(String publicKey) async {
    await fs.ensureDir('$homePath/.ssh');
    final trimmed = publicKey.trim();
    final targetBlob = _decodePublicKeyBlob(trimmed);

    var content = await fs.readString(path) ?? '';
    for (final line in content.split('\n')) {
      if (line.isEmpty) continue;
      final blob = _decodePublicKeyBlob(line);
      if (blob != null &&
          targetBlob != null &&
          _bytesEqual(blob, targetBlob)) {
        return;
      }
    }

    if (content.isNotEmpty && !content.endsWith('\n')) {
      content += '\n';
    }
    content += '$trimmed\n';
    await fs.atomicWrite(path, content);
    await _chmod600?.call(path);
  }

  Future<void> revoke(String publicKey) async {
    final trimmed = publicKey.trim();
    final targetBlob = _decodePublicKeyBlob(trimmed);
    if (targetBlob == null) return;

    final content = await fs.readString(path);
    if (content == null) return;

    final rawLines = content.split('\n');
    final kept = <String>[];
    var changed = false;
    for (var index = 0; index < rawLines.length; index++) {
      final line = rawLines[index];
      if (index == rawLines.length - 1 && line.isEmpty) continue;

      final blob = _decodePublicKeyBlob(line);
      if (blob != null && _bytesEqual(blob, targetBlob)) {
        changed = true;
        continue;
      }
      kept.add(line);
    }

    if (!changed) return;

    final newContent = kept.isEmpty ? '' : '${kept.join('\n')}\n';
    await fs.atomicWrite(path, newContent);
    await _chmod600?.call(path);
  }
}

List<int>? _decodePublicKeyBlob(String publicKeyLine) {
  final trimmed = publicKeyLine.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
  final fields = trimmed.split(RegExp(r'\s+'));
  if (fields.length < 2) return null;
  try {
    return base64.decode(base64.normalize(fields[1]));
  } on FormatException {
    return null;
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
