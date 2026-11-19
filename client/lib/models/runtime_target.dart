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

@immutable
class RuntimeTarget {
  const RuntimeTarget({
    required this.id,
    required this.label,
    required this.kind,
    this.sshProfileId,
    this.wslDistro,
    this.remoteOs,
  });

  static const String localId = 'local';
  static const termuxDefaultId = 'termux:default';

  factory RuntimeTarget.local({String label = 'This device'}) =>
      RuntimeTarget(id: localId, label: label, kind: RuntimeKind.local);

  factory RuntimeTarget.termux({String label = 'Termux'}) => RuntimeTarget(
    id: termuxDefaultId,
    label: label,
    kind: RuntimeKind.termux,
    sshProfileId: 'termux',
  );

  factory RuntimeTarget.wsl(String distro, {String? label}) => RuntimeTarget(
    id: 'wsl:$distro',
    label: label ?? 'WSL · $distro',
    kind: RuntimeKind.wsl,
    wslDistro: distro,
  );

  factory RuntimeTarget.ssh(String profileId, {required String label}) =>
      RuntimeTarget(
        id: 'ssh:$profileId',
        label: label,
        kind: RuntimeKind.ssh,
        sshProfileId: profileId,
      );

  final String id;
  final String label;
  final RuntimeKind kind;
  final String? sshProfileId;
  final String? wslDistro;
  final RemoteOs? remoteOs;

  /// The typed view of [id]. Decoding happens in exactly one place
  /// (`RuntimeTargetId.decode`); callers that need to dispatch on the kind of
  /// an id string should go through this instead of re-implementing prefixes.
  RuntimeTargetId get targetId => RuntimeTargetId.decode(id);

  factory RuntimeTarget.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String? ?? localId;
    final kindRaw = json['kind'] as String?;
    final kind = RuntimeKind.values.firstWhere(
      (e) => e.name == kindRaw,
      orElse: () => runtimeKindOfId(id),
    );
    final osRaw = json['remoteOs'] as String?;
    return RuntimeTarget(
      id: id,
      label: json['label'] as String? ?? id,
      kind: kind,
      sshProfileId: json['sshProfileId'] as String? ?? sshProfileIdOfId(id),
      wslDistro: json['wslDistro'] as String? ?? wslDistroOfId(id),
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
    'kind': kind.name,
    if (sshProfileId != null) 'sshProfileId': sshProfileId,
    if (wslDistro != null) 'wslDistro': wslDistro,
    if (remoteOs != null) 'remoteOs': remoteOs!.name,
  };

  RuntimeTarget copyWith({
    String? id,
    String? label,
    RuntimeKind? kind,
    String? sshProfileId,
    String? wslDistro,
    RemoteOs? remoteOs,
  }) => RuntimeTarget(
    id: id ?? this.id,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    sshProfileId: sshProfileId ?? this.sshProfileId,
    wslDistro: wslDistro ?? this.wslDistro,
    remoteOs: remoteOs ?? this.remoteOs,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeTarget &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          kind == other.kind &&
          sshProfileId == other.sshProfileId &&
          wslDistro == other.wslDistro &&
          remoteOs == other.remoteOs;

  @override
  int get hashCode =>
      Object.hash(id, label, kind, sshProfileId, wslDistro, remoteOs);
}
