import 'dart:typed_data';

import 'package:dartssh2/protocol.dart'
    show
        SSHEd25519PublicKey,
        SSHEd25519Signature,
        SSHMessageWriter,
        SSH_Message_Userauth_Request;

/// The only public key algorithm tp_sshd accepts for userauth: the spec's
/// device-key surface is ed25519 only.
const userauthKeyAlgorithm = 'ssh-ed25519';

/// Verifies the RFC 4252 §7 signature of a signed `publickey`
/// [SSH_Message_Userauth_Request].
///
/// The signed blob is the request re-encoded without the signature and
/// prefixed with the session identifier — byte-for-byte what the dartssh2
/// client signs (`SSHTransport.composeChallenge` in the fork):
///
/// ```
/// string    session identifier
/// byte      SSH_MSG_USERAUTH_REQUEST (50)
/// string    user name
/// string    service name
/// string    "publickey"
/// boolean   TRUE
/// string    public key algorithm name
/// string    public key blob
/// ```
///
/// Fails closed: a non-ed25519 algorithm, a malformed key or signature
/// frame, and any verification failure all return `false` — the caller
/// counts that as a failed authentication attempt.
bool verifyEd25519UserauthSignature({
  required Uint8List sessionId,
  required SSH_Message_Userauth_Request request,
}) {
  final publicKey = request.publicKey;
  final signature = request.signature;
  if (request.publicKeyAlgorithm != userauthKeyAlgorithm ||
      publicKey == null ||
      signature == null) {
    return false;
  }

  try {
    final key = SSHEd25519PublicKey.decode(publicKey);
    final decodedSignature = SSHEd25519Signature.decode(signature);

    final writer = SSHMessageWriter();
    writer.writeString(sessionId);
    writer.writeUint8(SSH_Message_Userauth_Request.messageId);
    writer.writeUtf8(request.user);
    writer.writeUtf8(request.serviceName);
    writer.writeUtf8('publickey');
    writer.writeBool(true);
    writer.writeUtf8(request.publicKeyAlgorithm!);
    writer.writeString(publicKey);
    return key.verify(writer.takeBytes(), decodedSignature);
  } on Object {
    // A malformed key or signature frame is a failed attempt, not a crash.
    return false;
  }
}
