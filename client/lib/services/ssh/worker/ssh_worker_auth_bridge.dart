import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../models/ssh_profile.dart';
import '../../../repositories/ssh_credential_store.dart';
import '../../../repositories/ssh_known_host_repository.dart';
import '../ssh_credentials_resolver.dart';
import 'ssh_worker_protocol.dart';

/// UI-isolate handler for credential and host-key challenges from an SSH
/// profile worker.
///
/// Secure storage and the host-key prompt remain here because neither can be
/// accessed safely from a background isolate. Secret values are returned only
/// in [SshWorkerAuthReply] and are never included in diagnostics.
class SshWorkerAuthBridge {
  SshWorkerAuthBridge({
    required SshCredentialStore credentialStore,
    required SshKnownHostRepository knownHostRepository,
    Future<bool> Function(HostKeyPromptInfo)? onHostKeyPrompt,
    void Function(String storageKey, String fingerprintHex)? onHostKeyPersist,
    SshWorkerDialTargetResolver? dialTargetResolver,
    VaultCredentialReader? vault,
    void Function(String message)? log,
  }) : _credentialStore = credentialStore,
       _hostKeyTrustPolicy = SshHostKeyTrustPolicy(
         knownHostRepository: knownHostRepository,
         onHostKeyPrompt: onHostKeyPrompt,
         onHostKeyPersist: onHostKeyPersist,
       ),
       _dialTargetResolver = dialTargetResolver,
       _vault = vault,
       _log = log;

  final SshCredentialStore _credentialStore;
  final SshHostKeyTrustPolicy _hostKeyTrustPolicy;
  final SshWorkerDialTargetResolver? _dialTargetResolver;
  final VaultCredentialReader? _vault;
  final void Function(String message)? _log;

  /// Resolves one challenge from the current worker generation.
  ///
  /// [profile] is supplied by the UI-side owner of that generation; the
  /// worker-provided id must match so a stale worker cannot request another
  /// profile's credentials.
  Future<SshWorkerAuthReply> replyTo(
    SshProfile profile,
    SshWorkerAuthChallenge challenge,
  ) async {
    if (challenge.profileId != profile.id) {
      throw StateError('SSH worker auth challenge profile mismatch');
    }
    _logSafeChallenge(profile.id, challenge.kind);
    switch (challenge.kind) {
      case SshWorkerAuthChallengeKind.password:
        return SshWorkerAuthReply.secret(
          requestId: challenge.requestId,
          value: await passwordFor(profile),
        );
      case SshWorkerAuthChallengeKind.privateKey:
        return SshWorkerAuthReply.secret(
          requestId: challenge.requestId,
          value: await privateKeyFor(profile),
        );
      case SshWorkerAuthChallengeKind.privateKeyPassphrase:
        return SshWorkerAuthReply.secret(
          requestId: challenge.requestId,
          value: await privateKeyPassphraseFor(profile),
        );
      case SshWorkerAuthChallengeKind.hostKey:
        return SshWorkerAuthReply.decision(
          requestId: challenge.requestId,
          value: await verifyHostKey(
            profile: profile,
            keyType: challenge.keyType!,
            fingerprint: challenge.fingerprint!,
          ),
        );
      case SshWorkerAuthChallengeKind.dialTarget:
        return SshWorkerAuthReply.dialTarget(
          requestId: challenge.requestId,
          value: await dialTargetFor(profile),
        );
    }
  }

  /// Returns the correlated UI reply handler for one worker generation.
  SshWorkerAuthChallengeHandler handlerFor(SshProfile profile) {
    return (challenge) => replyTo(profile, challenge);
  }

  Future<String?> _credential(SshProfile profile, String field) async {
    final entryId = profile.vaultEntryId;
    final vault = _vault;
    if (entryId != null && entryId.isNotEmpty && vault != null) {
      return vault(entryId, field);
    }
    return switch (field) {
      'password' => _credentialStore.loadPassword(profile.id),
      'privateKey' => _credentialStore.loadPrivateKey(profile.id),
      'passphrase' => _credentialStore.loadPrivateKeyPassphrase(profile.id),
      _ => null,
    };
  }

  Future<String?> passwordFor(SshProfile profile) =>
      _credential(profile, 'password');

  Future<String?> privateKeyFor(SshProfile profile) =>
      _credential(profile, 'privateKey');

  Future<String?> privateKeyPassphraseFor(SshProfile profile) =>
      _credential(profile, 'passphrase');

  Future<bool> verifyHostKey({
    required SshProfile profile,
    required String keyType,
    required Uint8List fingerprint,
  }) {
    return _hostKeyTrustPolicy.verify(
      profile: profile,
      keyType: keyType,
      fingerprint: fingerprint,
    );
  }

  /// Takes the relay decision before a generation begins and converts it to
  /// the immutable worker DTO. A later generation asks again.
  Future<SshWorkerDialTarget> dialTargetFor(SshProfile profile) async {
    final resolved = await _dialTargetResolver?.call(profile);
    return SshWorkerDialTarget(
      host: resolved?.address.address ?? profile.host,
      port: resolved?.port ?? profile.port,
      hostKeyFingerprints: List<String>.unmodifiable(
        profile.hostKeyFingerprints,
      ),
    );
  }

  void _logSafeChallenge(String profileId, SshWorkerAuthChallengeKind kind) {
    _log?.call('[ssh-worker-auth] profile=$profileId challenge=${kind.name}');
  }

  /// Canonical host-key identity for storage and prompts.
  static String fingerprintIdentity(Uint8List fingerprint) {
    final asText = utf8.decode(fingerprint, allowMalformed: true);
    if (asText.startsWith('SHA256:')) return asText;
    return fingerprintToHex(fingerprint);
  }

  static String fingerprintToHex(Uint8List fingerprint) {
    final buffer = StringBuffer();
    for (var i = 0; i < fingerprint.length; i++) {
      if (i > 0) buffer.write(':');
      buffer.write(fingerprint[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String fingerprintToBase64(Uint8List fingerprint) {
    final identity = fingerprintIdentity(fingerprint);
    return identity.startsWith('SHA256:')
        ? identity.substring('SHA256:'.length)
        : base64.encode(fingerprint);
  }
}

/// Resolves a relay target while UI-isolate state is available.
typedef SshWorkerDialTargetResolver =
    Future<({InternetAddress address, int port})?> Function(SshProfile profile);

class HostKeyPromptInfo {
  HostKeyPromptInfo({
    required this.profile,
    required this.keyType,
    required this.fingerprintHex,
    required this.fingerprintBase64,
    required this.isMismatch,
    this.previousFingerprintHex,
  });

  final SshProfile profile;
  final String keyType;
  final String fingerprintHex;
  final String fingerprintBase64;
  final bool isMismatch;
  final String? previousFingerprintHex;
}

/// Existing TOFU and pinned-host-key policy, kept in the UI isolate.
class SshHostKeyTrustPolicy {
  SshHostKeyTrustPolicy({
    required SshKnownHostRepository knownHostRepository,
    Future<bool> Function(HostKeyPromptInfo)? onHostKeyPrompt,
    void Function(String storageKey, String fingerprintHex)? onHostKeyPersist,
  }) : _knownHostRepository = knownHostRepository,
       _onHostKeyPrompt = onHostKeyPrompt,
       _onHostKeyPersist = onHostKeyPersist;

  final SshKnownHostRepository _knownHostRepository;
  final Future<bool> Function(HostKeyPromptInfo)? _onHostKeyPrompt;
  final void Function(String storageKey, String fingerprintHex)?
  _onHostKeyPersist;

  Future<bool> verify({
    required SshProfile profile,
    required String keyType,
    required Uint8List fingerprint,
  }) async {
    final storageKey = '${profile.hostIdentifier}::$keyType';
    final fingerprintHex = SshWorkerAuthBridge.fingerprintIdentity(fingerprint);
    final fingerprintBase64 = SshWorkerAuthBridge.fingerprintToBase64(
      fingerprint,
    );
    if (profile.hostKeyFingerprints.isNotEmpty) {
      return profile.hostKeyFingerprints.contains(fingerprintHex);
    }
    final existing = await _knownHostRepository.findFingerprint(
      profile.hostIdentifier,
      keyType,
    );
    if (existing == null) {
      if (_onHostKeyPrompt != null) {
        final accepted = await _onHostKeyPrompt(
          HostKeyPromptInfo(
            profile: profile,
            keyType: keyType,
            fingerprintHex: fingerprintHex,
            fingerprintBase64: fingerprintBase64,
            isMismatch: false,
          ),
        );
        if (!accepted) return false;
      }
      await _knownHostRepository.saveFingerprint(
        profile.hostIdentifier,
        keyType,
        fingerprintHex,
      );
      _onHostKeyPersist?.call(storageKey, fingerprintHex);
      return true;
    }
    if (existing == fingerprintHex) return true;
    if (_onHostKeyPrompt == null) return false;
    final accepted = await _onHostKeyPrompt(
      HostKeyPromptInfo(
        profile: profile,
        keyType: keyType,
        fingerprintHex: fingerprintHex,
        fingerprintBase64: fingerprintBase64,
        isMismatch: true,
        previousFingerprintHex: existing,
      ),
    );
    if (!accepted) return false;
    await _knownHostRepository.saveFingerprint(
      profile.hostIdentifier,
      keyType,
      fingerprintHex,
    );
    _onHostKeyPersist?.call(storageKey, fingerprintHex);
    return true;
  }
}
