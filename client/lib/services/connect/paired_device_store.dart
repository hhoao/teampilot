import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../io/filesystem.dart';

typedef GrantGenerator = String Function();

/// Desktop-side registry of paired phones' relay grants and device keys.
///
/// Only the SHA-256 hex digest of a grant is ever persisted
/// (`connect/grants.json`); the raw token lives solely on the phone. A grant
/// is scoped to one `deviceId` plus this install's `hostId`, and comparisons
/// run in constant time.
///
/// Device public keys are registered in a separate file
/// (`connect/devices.json`) in the OpenSSH one-line format
/// (`ssh-ed25519 <base64> [comment]`); they are not host-scoped. Key blobs
/// are compared in constant time as well.
class PairedDeviceStore {
  PairedDeviceStore({
    required this.fs,
    required this.appDataRoot,
    GrantGenerator? generateGrant,
  }) : _generateGrant =
           generateGrant ??
           (() => base64Url
               .encode(
                 List<int>.generate(32, (_) => Random.secure().nextInt(256)),
               )
               .replaceAll('=', ''));

  final Filesystem fs;
  final String appDataRoot;
  final GrantGenerator _generateGrant;

  final _registryChanged = StreamController<void>.broadcast();

  /// Fires after every device-key registry mutation (issue / revoke).
  Stream<void> get deviceRegistryChanged => _registryChanged.stream;

  String get grantsPath =>
      fs.pathContext.join(appDataRoot, 'connect', 'grants.json');

  String get devicesPath =>
      fs.pathContext.join(appDataRoot, 'connect', 'devices.json');

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

  /// Removes every trace of [deviceId] — its relay grant and its registered
  /// public key — returning whether anything changed.
  Future<bool> revokeDevice(String deviceId) async {
    final grants = await _loadDevices();
    final nextGrants = grants
        .where((entry) => entry.deviceId != deviceId)
        .toList(growable: false);
    final grantChanged = nextGrants.length != grants.length;
    if (grantChanged) {
      await _writeDevices(nextGrants);
    }

    final devices = await _loadDeviceEntries();
    final nextDevices = devices
        .where((entry) => entry.deviceId != deviceId)
        .toList(growable: false);
    final deviceChanged = nextDevices.length != devices.length;
    if (deviceChanged) {
      await _writeDeviceEntries(nextDevices);
    }

    if (grantChanged || deviceChanged) {
      _registryChanged.add(null);
      return true;
    }
    return false;
  }

  Future<bool> hasDevice(String deviceId) async {
    return (await _loadDevices()).any((entry) => entry.deviceId == deviceId);
  }

  /// Lists the registered device keys with their optional display names, for
  /// the Connect UI's paired-device list. A pure read of `connect/devices.json`.
  Future<List<({String deviceId, String? deviceName})>> listDevices() async {
    return [
      for (final entry in await _loadDeviceEntries())
        (deviceId: entry.deviceId, deviceName: entry.deviceName),
    ];
  }

  /// Registers (or replaces) the public key of [deviceId].
  ///
  /// [publicKey] is the OpenSSH one-line format
  /// `ssh-ed25519 <base64> [comment]`, as posted by the phone during pairing.
  Future<void> issueDevice({
    required String deviceId,
    required String publicKey,
    String? deviceName,
  }) async {
    final devices = (await _loadDeviceEntries()).toList()
      ..removeWhere((entry) => entry.deviceId == deviceId)
      ..add(
        _DeviceEntry(
          deviceId: deviceId,
          deviceName: deviceName,
          publicKey: publicKey.trim(),
        ),
      );
    await _writeDeviceEntries(devices);
    _registryChanged.add(null);
  }

  /// Whether [publicKeyLine] matches any registered device key.
  ///
  /// The comparison runs in constant time over the decoded key blobs, so a
  /// trailing comment on either line is irrelevant.
  Future<bool> isValidDeviceKey(String publicKeyLine) =>
      deviceIdForPublicKey(publicKeyLine).then((deviceId) => deviceId != null);

  /// The id of the device whose registered key matches [publicKeyLine], or
  /// `null` when no registered key matches (including malformed lines).
  Future<String?> deviceIdForPublicKey(String publicKeyLine) async {
    final blob = _decodePublicKeyBlob(publicKeyLine);
    if (blob == null) return null;
    String? matched;
    // Scan every entry — no early exit on a hit, so the number of key
    // comparisons does not leak which entry matched.
    for (final entry in await _loadDeviceEntries()) {
      final entryBlob = _decodePublicKeyBlob(entry.publicKey);
      if (entryBlob == null) continue;
      if (_constantTimeBytesEquals(entryBlob, blob)) {
        matched = entry.deviceId;
      }
    }
    return matched;
  }

  /// Closes [deviceRegistryChanged]. Call during app teardown.
  void dispose() => _registryChanged.close();

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

  Future<List<_DeviceEntry>> _loadDeviceEntries() async {
    final contents = await fs.readString(devicesPath);
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
              entry['publicKey'] is String)
            _DeviceEntry(
              deviceId: entry['deviceId'] as String,
              deviceName: entry['deviceName'] is String
                  ? entry['deviceName'] as String
                  : null,
              publicKey: entry['publicKey'] as String,
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _writeDeviceEntries(List<_DeviceEntry> devices) async {
    await fs.ensureDir(fs.pathContext.dirname(devicesPath));
    await fs.atomicWrite(
      devicesPath,
      jsonEncode({
        'v': 1,
        'devices': [
          for (final device in devices)
            {
              'deviceId': device.deviceId,
              if (device.deviceName != null) 'deviceName': device.deviceName,
              'publicKey': device.publicKey,
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

class _DeviceEntry {
  const _DeviceEntry({
    required this.deviceId,
    this.deviceName,
    required this.publicKey,
  });

  final String deviceId;
  final String? deviceName;
  final String publicKey;
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}

bool _constantTimeBytesEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

/// Decodes the base64 key blob out of an OpenSSH one-line public key
/// (`<type> <base64> [comment]`), or `null` when the line is not one.
List<int>? _decodePublicKeyBlob(String publicKeyLine) {
  final fields = publicKeyLine.trim().split(RegExp(r'\s+'));
  if (fields.length < 2) return null;
  try {
    return base64.decode(fields[1]);
  } on FormatException {
    return null;
  }
}
