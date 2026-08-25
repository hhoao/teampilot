import 'package:uuid/uuid.dart';

import '../../models/ssh_profile.dart';
import '../../models/ssh_reachability.dart';
import '../../repositories/ssh_credential_store.dart';
import '../../repositories/ssh_known_host_repository.dart';
import '../../repositories/ssh_profile_repository.dart';
import 'pairing_http.dart';
import 'ssh_pairing_offer.dart';

/// Persists the phone's SSH connection after a desktop accepts a pairing POST.
class PairedProfileWriter {
  PairedProfileWriter({
    required SshProfileRepository profileRepository,
    required SshCredentialStore credentialStore,
    required SshKnownHostRepository knownHostRepository,
    String Function()? idFactory,
    DateTime Function()? now,
  }) : _profileRepository = profileRepository,
       _credentialStore = credentialStore,
       _knownHostRepository = knownHostRepository,
       _idFactory = idFactory ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final SshProfileRepository _profileRepository;
  final SshCredentialStore _credentialStore;
  final SshKnownHostRepository _knownHostRepository;
  final String Function() _idFactory;
  final DateTime Function() _now;

  Future<SshProfile> upsert({
    required SshPairingOffer offer,
    required PairingPostResult result,
    required String devicePem,
  }) async {
    if (!result.ok) {
      throw ArgumentError.value(result, 'result', 'pairing was not accepted');
    }
    final lanEndpoint = offer.endpoints
        .where((endpoint) => endpoint.kind == SshEndpointKind.lan)
        .firstOrNull;
    if (lanEndpoint == null) {
      throw ArgumentError.value(offer, 'offer', 'must contain a LAN endpoint');
    }

    final profiles = await _profileRepository.loadAll();
    final previous = profiles
        .where((profile) => profile.pairedDesktopId == offer.hostId)
        .firstOrNull;
    final timestamp = _now().millisecondsSinceEpoch;
    final profile = SshProfile(
      id: previous?.id ?? _idFactory(),
      name: result.profileHint.trim().isEmpty
          ? offer.displayName
          : result.profileHint,
      host: lanEndpoint.host,
      port: lanEndpoint.port,
      username: offer.username,
      authType: SshAuthType.privateKey,
      createdAt: previous?.createdAt ?? timestamp,
      updatedAt: timestamp,
      lastAppDataRoot: offer.appDataRoot,
      endpoints: offer.endpoints,
      hostKeyFingerprints: offer.hostKeyFingerprints,
      pairedDesktopId: offer.hostId,
      relayUrl: offer.relay?.url,
      lastGoodKind: SshEndpointKind.lan,
    );

    await _profileRepository.save(profile);
    await _credentialStore.savePrivateKey(profile.id, devicePem);
    await _saveKnownHostPins(offer);
    return profile;
  }

  Future<void> _saveKnownHostPins(SshPairingOffer offer) async {
    // The legacy TOFU cache can represent only one fingerprint per host/key
    // type. Paired profiles use their complete fingerprint list directly, so
    // skip this compatibility cache rather than discard a rotation pin.
    if (offer.hostKeyFingerprints.length != 1) return;
    final fingerprint = offer.hostKeyFingerprints.single;
    final endpoints = offer.endpoints.where(
      (endpoint) =>
          endpoint.kind == SshEndpointKind.lan ||
          endpoint.kind == SshEndpointKind.extra,
    );
    for (final endpoint in endpoints) {
      final hostIdentifier =
          '${offer.username}@${endpoint.host}:${endpoint.port}';
      await _knownHostRepository.saveFingerprint(
        hostIdentifier,
        'ssh-ed25519',
        fingerprint,
      );
    }
  }
}
