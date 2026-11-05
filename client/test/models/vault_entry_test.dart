import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/vault_entry.dart';

void main() {
  test('round-trips every built-in type', () {
    for (final type in VaultEntryType.values) {
      final entry = VaultEntry(
        id: 'id-${type.storageValue}',
        type: type,
        title: 'title',
        fields: {for (final f in type.defaultFields) f: 'v-$f'},
        tags: const ['work'],
        notes: 'note',
        favorite: true,
        revealable: type != VaultEntryType.sshPrivateKey,
        createdAt: 1,
        updatedAt: 2,
      );
      expect(VaultEntry.fromJson(entry.toJson()), entry);
    }
  });

  test(
    'unknown type falls back to custom and keeps unknown top-level keys',
    () {
      final entry = VaultEntry.fromJson({
        'id': 'a',
        'type': 'future_type',
        'title': 'x',
        'fields': {'k': 'v'},
        'unknownTopLevel': 42,
      });
      expect(entry.type, VaultEntryType.custom);
      expect(entry.extra['unknownTopLevel'], 42);
      expect(entry.toJson()['unknownTopLevel'], 42);
    },
  );

  test(
    'secret fields are masked per type and custom fields are always secret',
    () {
      const ssh = VaultEntry(
        id: '1',
        type: VaultEntryType.sshPassword,
        title: 's',
      );
      expect(ssh.isSecretField('password'), isTrue);
      expect(ssh.isSecretField('username'), isFalse);

      const custom = VaultEntry(
        id: '2',
        type: VaultEntryType.custom,
        title: 'c',
      );
      expect(custom.isSecretField('anything'), isTrue);
    },
  );

  test('relay grants are masked for both SSH entry types', () {
    const password = VaultEntry(
      id: '1',
      type: VaultEntryType.sshPassword,
      title: 'p',
    );
    expect(password.isSecretField('relayGrant'), isTrue);
    expect(password.isSecretField('password'), isTrue);
    expect(password.isSecretField('host'), isFalse);
    expect(password.isSecretField('username'), isFalse);

    const key = VaultEntry(
      id: '2',
      type: VaultEntryType.sshPrivateKey,
      title: 'k',
    );
    expect(key.isSecretField('relayGrant'), isTrue);
    expect(key.isSecretField('privateKey'), isTrue);
    expect(key.isSecretField('passphrase'), isTrue);
  });

  test('private keys are never revealable', () {
    const entry = VaultEntry(
      id: '1',
      type: VaultEntryType.sshPrivateKey,
      title: 'k',
      revealable: true,
    );
    expect(entry.revealAllowed, isFalse);
  });

  test('toString never contains field values', () {
    const entry = VaultEntry(
      id: '1',
      type: VaultEntryType.apiKey,
      title: 'openai',
      fields: {'apiKey': 'sk-super-secret'},
    );
    expect(entry.toString(), isNot(contains('sk-super-secret')));
  });
}
