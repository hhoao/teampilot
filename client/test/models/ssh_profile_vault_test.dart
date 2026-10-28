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

  test('profiles differing only by vaultEntryId are not equal', () {
    const base = SshProfile(id: 'p1', name: 'S', host: 'h', username: 'u');
    final linked = base.copyWith(vaultEntryId: 'v1');
    expect(linked, isNot(base));
    expect(linked.hashCode, isNot(base.hashCode));
  });
}
