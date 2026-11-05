// Backwards-compatible import surface for the credential-link parser.
//
// New code should import `vault_ref.dart` directly; this file stays so older
// call sites keep working while the typed reference replaces string checks.
export 'vault_ref.dart';
