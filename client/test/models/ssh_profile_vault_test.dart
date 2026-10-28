import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';

void main() {
  test('vaultEntryId round-trips', () {
    const profile = SshProfile(
      id: 'p1', name: 'Server', host: 'example.com', username: 'u',
      vaultEntryId: 'v1',
    );
    expect(SshProfile.fromJson(profile.toJson()).vaultEntryId, 'v1');
  });

  test('missing vaultEntryId stays null and is not serialized', () {
    const profile = SshProfile(
      id: 'p1', name: 'Server', host: 'example.com', username: 'u',
    );
    final json = profile.toJson();
    expect(json.containsKey('vaultEntryId'), isFalse);
    expect(SshProfile.fromJson(json).vaultEntryId, isNull);
  });
}
