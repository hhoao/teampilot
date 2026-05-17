import 'package:flutter/foundation.dart';

@immutable
class SshKnownHostEntry {
  const SshKnownHostEntry({
    required this.hostIdentifier,
    required this.keyType,
    required this.fingerprintHex,
  });

  factory SshKnownHostEntry.fromJson(Map<String, Object?> json) {
    return SshKnownHostEntry(
      hostIdentifier: json['hostIdentifier'] as String? ?? '',
      keyType: json['keyType'] as String? ?? '',
      fingerprintHex: json['fingerprintHex'] as String? ?? '',
    );
  }

  final String hostIdentifier;
  final String keyType;
  final String fingerprintHex;

  Map<String, Object?> toJson() {
    return {
      'hostIdentifier': hostIdentifier,
      'keyType': keyType,
      'fingerprintHex': fingerprintHex,
    };
  }

  String get storageKey => '$hostIdentifier::$keyType';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SshKnownHostEntry &&
            hostIdentifier == other.hostIdentifier &&
            keyType == other.keyType &&
            fingerprintHex == other.fingerprintHex;
  }

  @override
  int get hashCode => Object.hash(hostIdentifier, keyType, fingerprintHex);
}
