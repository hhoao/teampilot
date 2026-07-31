import 'dart:io';

import '../../repositories/ssh_credential_store.dart';
import '../storage/app_storage.dart';
import 'termux_openssh_ed25519_encoder.dart';

/// Device-local ed25519 key pair for Termux loopback SSH.
abstract final class TermuxKeyMaterial {
  static const credentialProfileId = 'termux';

  static String privateKeyPath(String nativeAppDataPath) {
    return AppPaths.pathContextForDataRoot(
      nativeAppDataPath,
    ).join(nativeAppDataPath, '.termux', 'ssh', 'id_ed25519');
  }

  static String publicKeyPath(String nativeAppDataPath) {
    return AppPaths.pathContextForDataRoot(
      nativeAppDataPath,
    ).join(nativeAppDataPath, '.termux', 'ssh', 'id_ed25519.pub');
  }

  static Future<void> ensureKeyPair({
    required String nativeAppDataPath,
    required SshCredentialStore credentials,
    TermuxOpenSshEd25519Encoder encoder = const TermuxOpenSshEd25519Encoder(),
  }) async {
    final privatePath = privateKeyPath(nativeAppDataPath);
    final publicPath = publicKeyPath(nativeAppDataPath);
    final privateFile = File(privatePath);
    final publicFile = File(publicPath);

    if (!await privateFile.exists()) {
      final pair = encoder.generate();
      await privateFile.parent.create(recursive: true);
      await privateFile.writeAsString(pair.privateKeyPem);
      await publicFile.writeAsString(pair.publicKeyOpenSsh);
      await credentials.savePrivateKey(credentialProfileId, pair.privateKeyPem);
      return;
    }

    final pem = await privateFile.readAsString();
    final stored = await credentials.loadPrivateKey(credentialProfileId);
    if (stored == null || stored.isEmpty) {
      await credentials.savePrivateKey(credentialProfileId, pem);
    }
  }

  static Future<String> publicKeyOpenSsh(String nativeAppDataPath) async {
    final publicPath = publicKeyPath(nativeAppDataPath);
    final content = await File(publicPath).readAsString();
    return content.trim();
  }
}
