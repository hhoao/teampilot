import 'credential_capture.dart';

/// Captures a vault entry and persists the owner reference atomically.
///
/// The guard exists so the four owner writers (SSH profile, app provider,
/// managed provider, GitHub) share the same ordering and rollback: a failed
/// catalog write never leaves the vault ahead of the owner. A rollback failure
/// is swallowed so the original persistence error survives.
Future<T> captureThenPersist<T>({
  required VaultCredentialCapture capture,
  required Future<VaultCaptureResult> Function() captureEntry,
  required Future<T> Function(VaultCaptureResult result) persist,
}) async {
  final result = await captureEntry();
  try {
    return await persist(result);
  } on Object {
    try {
      await capture.rollback(result);
    } on Object {
      // Preserve the persistence error; later cleanup can remove orphans.
    }
    rethrow;
  }
}
