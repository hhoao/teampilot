import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/services/cli/grok/grok_constants.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 11, 0, 0);

  test('lease is usable only with a token and a future expiry', () {
    final usable = CredentialLease(
      accessToken: 'tok',
      expiresAt: now.add(const Duration(minutes: 30)),
      epoch: 3,
    );
    expect(usable.isUsable(now), isTrue);
    expect(usable.isUsable(now.add(const Duration(hours: 1))), isFalse);
    expect(
      CredentialLease(
        accessToken: '',
        expiresAt: now.add(const Duration(minutes: 30)),
        epoch: 0,
      ).isUsable(now),
      isFalse,
    );
  });

  test('toProviderJson matches grok external auth provider stdout contract', () {
    final lease = CredentialLease(
      accessToken: 'tok',
      expiresAt: now.add(const Duration(seconds: 1800)),
      epoch: 7,
    );
    expect(lease.expiresInSeconds(now), 1800);
    expect(lease.toProviderJson(now),
        '{"access_token":"tok","expires_in":1800}');
  });

  test('grok constants expose the new env key and file names', () {
    expect(GrokConstants.authProviderCommandEnvKey,
        'GROK_AUTH_PROVIDER_COMMAND');
    expect(GrokConstants.leaseConfigFileName, 'credential-lease.json');
    expect(GrokConstants.leaseShimFileName, 'teampilot-grok-auth');
  });

  test('grok constants expose the ACP oauth method id', () {
    expect(GrokConstants.oauthMethodId, 'grok.com');
  });

  test('CredentialUnavailableException carries the health', () {
    expect(
      const CredentialUnavailableException(CredentialHealth.rejected).health,
      CredentialHealth.rejected,
    );
  });
}
