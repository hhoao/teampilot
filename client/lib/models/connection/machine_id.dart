/// Stable identity of a machine.
///
/// Reuses the profile UUID that every existing artifact already points at
/// (session targets, vault owners, known-host rows, paired-desktop links), so
/// the identity rename is a schema reshape rather than a foreign-key rewrite.
extension type const MachineId(String value) {
  bool get isNotEmpty => value.isNotEmpty;
  bool get isEmpty => value.isEmpty;
}
