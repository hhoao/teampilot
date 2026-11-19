import 'package:flutter/foundation.dart';

import 'runtime_target_id.dart';

export 'runtime_target_id.dart'
    show
        LocalTargetId,
        RuntimeKind,
        RuntimeTargetId,
        SshTargetId,
        TermuxTargetId,
        WslTargetId,
        usesSshTransport;

/// Probed for ssh targets at connect (P3). P0 always null.
enum RemoteOs { posix, windows }

RuntimeKind runtimeKindOfId(String id) => RuntimeTargetId.decode(id).kind;

String? wslDistroOfId(String id) => RuntimeTargetId.decode(id).wslDistro;

String? sshProfileIdOfId(String id) => RuntimeTargetId.decode(id).sshProfileId;

/// A place work runs: the encoding is the identity.
///
/// `kind`, `sshProfileId` and `wslDistro` are **derived** from [id] — they are
/// not stored alongside it, so a target can never claim to be an SSH machine
/// while carrying a local id (or the reverse).
@immutable
class RuntimeTarget {
  const RuntimeTarget({required this.id, required this.label, this.remoteOs});

  static const String localId = 'local';
  static const String termuxDefaultId = 'termux:default';

  factory RuntimeTarget.local({String label = 'This device'}) =>
      RuntimeTarget(id: localId, label: label);

  factory RuntimeTarget.termux({String label = 'Termux'}) =>
      RuntimeTarget(id: termuxDefaultId, label: label);

  factory RuntimeTarget.wsl(String distro, {String? label}) =>
      RuntimeTarget(id: 'wsl:$distro', label: label ?? 'WSL · $distro');

  factory RuntimeTarget.ssh(String profileId, {required String label}) =>
      RuntimeTarget(id: 'ssh:$profileId', label: label);

  final String id;
  final String label;
  final RemoteOs? remoteOs;

  /// The typed view of [id]. Decoding happens in exactly one place
  /// (`RuntimeTargetId.decode`); callers that need to dispatch on the kind of
  /// an id string should go through this instead of re-implementing prefixes.
  RuntimeTargetId get targetId => RuntimeTargetId.decode(id);

  RuntimeKind get kind => targetId.kind;

  String? get sshProfileId => targetId.sshProfileId;

  String? get wslDistro => targetId.wslDistro;

  factory RuntimeTarget.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String? ?? localId;
    final osRaw = json['remoteOs'] as String?;
    return RuntimeTarget(
      id: id,
      label: json['label'] as String? ?? id,
      remoteOs: osRaw == null
          ? null
          : RemoteOs.values.firstWhere(
              (e) => e.name == osRaw,
              orElse: () => RemoteOs.posix,
            ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (remoteOs != null) 'remoteOs': remoteOs!.name,
  };

  RuntimeTarget copyWith({String? id, String? label, RemoteOs? remoteOs}) =>
      RuntimeTarget(
        id: id ?? this.id,
        label: label ?? this.label,
        remoteOs: remoteOs ?? this.remoteOs,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeTarget &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          remoteOs == other.remoteOs;

  @override
  int get hashCode => Object.hash(id, label, remoteOs);
}
