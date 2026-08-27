import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../io/filesystem.dart';

typedef GrantGenerator = String Function();

/// Desktop-side registry of paired phones' relay grants.
///
/// Only the SHA-256 hex digest of a grant is ever persisted
/// (`connect/grants.json`); the raw token lives solely on the phone. A grant
/// is scoped to one `deviceId` plus this install's `hostId`, and comparisons
/// run in constant time.
class PairedDeviceStore {
  PairedDeviceStore({
    required this.fs,
    required this.appDataRoot,
    GrantGenerator? generateGrant,
  }) : _generateGrant =
           generateGrant ??
           (() =>
               base64Url
                   .encode(
                     List<int>.generate(
                       32,
                       (_) => Random.secure().nextInt(256),
                     ),
                   )
                   .replaceAll('=', ''));

  final Filesystem fs;
  final String appDataRoot;
  final GrantGenerator _generateGrant;

  String get grantsPath =>
      fs.pathContext.join(appDataRoot, 'connect', 'grants.json');

  String generateGrant() => _generateGrant();

  Future<String> issueGrant({
    required String hostId,
    required String deviceId,
    String? grant,
  }) async {
    final token = grant ?? _generateGrant();
    final devices = (await _loadDevices()).toList()
      ..removeWhere((entry) => entry.deviceId == deviceId)
      ..add(
        _PairedDevice(
          deviceId: deviceId,
          hostId: hostId,
          grantSha256: sha256.convert(utf8.encode(token)).toString(),
        ),
      );
    await _writeDevices(devices);
    return token;
  }

  Future<bool> validateGrant({
    required String hostId,
    required String deviceId,
    required String grant,
  }) async {
    if (deviceId.isEmpty || grant.isEmpty) return false;
    final expected = _hash(grant);
    for (final entry in await _loadDevices()) {
      if (entry.deviceId != deviceId || entry.hostId != hostId) continue;
      if (_constantTimeEquals(entry.grantSha256, expected)) return true;
    }
    return false;
  }

  Future<bool> revokeDevice(String deviceId) async {
    final devices = await _loadDevices();
    final next = devices
        .where((entry) => entry.deviceId != deviceId)
        .toList(growable: false);
    if (next.length == devices.length) return false;
    await _writeDevices(next);
    return true;
  }

  Future<bool> hasDevice(String deviceId) async {
    return (await _loadDevices()).any((entry) => entry.deviceId == deviceId);
  }

  String _hash(String grant) => sha256.convert(utf8.encode(grant)).toString();

  Future<List<_PairedDevice>> _loadDevices() async {
    final contents = await fs.readString(grantsPath);
    if (contents == null || contents.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map) return const [];
      final raw = decoded['devices'];
      if (raw is! List) return const [];
      return [
        for (final entry in raw)
          if (entry is Map &&
              entry['deviceId'] is String &&
              entry['hostId'] is String &&
              entry['grantSha256'] is String)
            _PairedDevice(
              deviceId: entry['deviceId'] as String,
              hostId: entry['hostId'] as String,
              grantSha256: entry['grantSha256'] as String,
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _writeDevices(List<_PairedDevice> devices) async {
    await fs.ensureDir(fs.pathContext.dirname(grantsPath));
    await fs.atomicWrite(
      grantsPath,
      jsonEncode({
        'v': 1,
        'devices': [
          for (final device in devices)
            {
              'deviceId': device.deviceId,
              'hostId': device.hostId,
              'grantSha256': device.grantSha256,
            },
        ],
      }),
    );
  }
}

class _PairedDevice {
  const _PairedDevice({
    required this.deviceId,
    required this.hostId,
    required this.grantSha256,
  });

  final String deviceId;
  final String hostId;
  final String grantSha256;
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
