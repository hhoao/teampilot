import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/services/connect/connect_pair_client.dart';
import 'package:teampilot/services/connect/pairing_certificate.dart';
import 'package:teampilot/services/connect/pairing_http.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';

SshPairingOffer _offer({SshPairingSession? pairing}) => SshPairingOffer(
  v: 1,
  hostId: 'AbCdEf0123_-xyZ9',
  username: 'alice',
  displayName: 'Alice desktop',
  appDataRoot: '/home/alice/.local/share/com.hhoa.teampilot',
  endpoints: const [
    SshReachabilityEndpoint(
      kind: SshEndpointKind.lan,
      host: '192.168.1.20',
      port: 22,
    ),
  ],
  hostKeyFingerprints: const ['SHA256:host-key'],
  pairing:
      pairing ??
      const SshPairingSession(
        token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
        expiresAt: 1770000000000,
        url: 'https://192.168.1.20:2768/pair',
        tlsCertSha256: 'deadbeef',
      ),
);

class _RecordingTransport implements PairingPostTransport {
  var posts = 0;
  Uri? url;
  Map<String, Object?>? body;
  String? tlsCertSha256;

  @override
  Future<PairingPostResult> post({
    required Uri url,
    required Map<String, Object?> body,
    required String tlsCertSha256,
  }) async {
    posts++;
    this.url = url;
    this.body = body;
    this.tlsCertSha256 = tlsCertSha256;
    return const PairingPostResult(ok: true, profileHint: 'desktop');
  }
}

void main() {
  test(
    'posts pairing data through a transport pinned to the offer certificate',
    () async {
      final transport = _RecordingTransport();
      final client = ConnectPairClient(transport: transport);
      final pairingOffer = _offer();

      final result = await client.pair(
        offer: pairingOffer,
        deviceId: 'phone-1',
        deviceName: 'Pixel',
        publicKey: 'ssh-ed25519 AAAA',
      );

      expect(result.ok, isTrue);
      expect(transport.url, Uri.parse(pairingOffer.pairing.url));
      expect(transport.tlsCertSha256, pairingOffer.pairing.tlsCertSha256);
      expect(transport.body, {
        'token': pairingOffer.pairing.token,
        'deviceId': 'phone-1',
        'deviceName': 'Pixel',
        'publicKey': 'ssh-ed25519 AAAA',
      });
    },
  );

  test('rejects non-HTTPS pairing offers before sending the token', () async {
    final transport = _RecordingTransport();
    final client = ConnectPairClient(transport: transport);

    await expectLater(
      client.pair(
        offer: _offer(
          pairing: const SshPairingSession(
            token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
            expiresAt: 1770000000000,
            url: 'http://192.168.1.20:2768/pair',
            tlsCertSha256: 'deadbeef',
          ),
        ),
        deviceId: 'phone-1',
        deviceName: 'Pixel',
        publicKey: 'ssh-ed25519 AAAA',
      ),
      throwsA(
        isA<ConnectPairClientException>().having(
          (error) => error.code,
          'code',
          'invalidUrl',
        ),
      ),
    );
    expect(transport.posts, 0);
  });

  test(
    'direct transport sends the token only after the TLS DER pin matches',
    () async {
      final directory = await Directory.systemTemp.createTemp('pairing_cert_');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final certificate = await ConnectTls().generate(
        appDataRoot: directory.path,
      );
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        certificate.tlsContext as SecurityContext,
      );
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        await utf8.decoder.bind(request).join();
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(const {'ok': true, 'profileHint': 'desktop'}));
        await request.response.close();
      });
      final client = ConnectPairClient();
      final pairing = SshPairingSession(
        token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
        expiresAt: 1770000000000,
        url: 'https://127.0.0.1:${server.port}/pair',
        tlsCertSha256: certificate.sha256Hex,
      );

      await expectLater(
        client.pair(
          offer: _offer(pairing: pairing),
          deviceId: 'phone-1',
          deviceName: 'Pixel',
          publicKey: 'ssh-ed25519 AAAA',
        ),
        completion(isA<PairingPostResult>()),
      );
      expect(requests, 1);

      await expectLater(
        client.pair(
          offer: _offer(
            pairing: SshPairingSession(
              token: pairing.token,
              expiresAt: pairing.expiresAt,
              url: pairing.url,
              tlsCertSha256: '0' * 64,
            ),
          ),
          deviceId: 'phone-1',
          deviceName: 'Pixel',
          publicKey: 'ssh-ed25519 AAAA',
        ),
        throwsA(isA<HandshakeException>()),
      );
      expect(requests, 1);
    },
  );
}
