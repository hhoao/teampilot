/// Where files live and processes run for a unit of work.
enum RuntimeKind { local, wsl, ssh, termux }

/// Probed for ssh targets at connect (P3). P0 always null.
enum RemoteOs { posix, windows }

/// The typed identity of a [RuntimeTarget].
///
/// The persisted form is the string returned by [encode]; decoding lives here
/// and nowhere else, so "which kind is this id" can never be answered by an
/// ad-hoc `startsWith` check somewhere else in the app.
sealed class RuntimeTargetId {
  const RuntimeTargetId();

  /// Decodes the persisted form. Unknown ids are local: that is the historical
  /// default and the only kind that needs no remote setup.
  factory RuntimeTargetId.decode(String raw) {
    if (raw.startsWith('ssh:')) return SshTargetId(raw.substring(4));
    if (raw.startsWith('wsl:')) return WslTargetId(raw.substring(4));
    if (raw.startsWith('termux:')) return const TermuxTargetId();
    return const LocalTargetId();
  }

  static const local = LocalTargetId();
  static const termux = TermuxTargetId();

  String encode();

  RuntimeKind get kind;

  String? get sshProfileId => null;

  String? get wslDistro => null;
}

final class LocalTargetId extends RuntimeTargetId {
  const LocalTargetId();

  @override
  String encode() => 'local';

  @override
  RuntimeKind get kind => RuntimeKind.local;

  @override
  bool operator ==(Object other) => other is LocalTargetId;

  @override
  int get hashCode => (LocalTargetId).hashCode;
}

final class WslTargetId extends RuntimeTargetId {
  const WslTargetId(this.distro);

  final String distro;

  @override
  String encode() => 'wsl:$distro';

  @override
  RuntimeKind get kind => RuntimeKind.wsl;

  @override
  String? get wslDistro => distro;

  @override
  bool operator ==(Object other) =>
      other is WslTargetId && other.distro == distro;

  @override
  int get hashCode => Object.hash(WslTargetId, distro);
}

final class SshTargetId extends RuntimeTargetId {
  const SshTargetId(this.profileId);

  final String profileId;

  @override
  String encode() => 'ssh:$profileId';

  @override
  RuntimeKind get kind => RuntimeKind.ssh;

  @override
  String? get sshProfileId => profileId;

  @override
  bool operator ==(Object other) =>
      other is SshTargetId && other.profileId == profileId;

  @override
  int get hashCode => Object.hash(SshTargetId, profileId);
}

/// Termux targets ride the SSH transport through a synthetic loopback profile.
final class TermuxTargetId extends RuntimeTargetId {
  const TermuxTargetId();

  @override
  String encode() => 'termux:default';

  @override
  RuntimeKind get kind => RuntimeKind.termux;

  @override
  String? get sshProfileId => 'termux';

  @override
  bool operator ==(Object other) => other is TermuxTargetId;

  @override
  int get hashCode => (TermuxTargetId).hashCode;
}

/// SSH transport targets (catalog SSH + synthetic Termux loopback profile).
bool usesSshTransport(RuntimeKind kind) =>
    kind == RuntimeKind.ssh || kind == RuntimeKind.termux;
