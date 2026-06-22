import 'package:flutter/foundation.dart';

/// Where files live and processes run for a unit of work. P0: one global
/// default target reproduces today's behavior; P2 attaches targets per folder.
enum RuntimeKind { local, wsl, ssh }

/// Probed for ssh targets at connect (P3). P0 always null.
enum RemoteOs { posix, windows }

RuntimeKind runtimeKindOfId(String id) {
  if (id.startsWith('wsl:')) return RuntimeKind.wsl;
  if (id.startsWith('ssh:')) return RuntimeKind.ssh;
  return RuntimeKind.local;
}

String? wslDistroOfId(String id) =>
    id.startsWith('wsl:') ? id.substring(4) : null;

String? sshProfileIdOfId(String id) =>
    id.startsWith('ssh:') ? id.substring(4) : null;

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

  factory RuntimeTarget.local({String label = 'This device'}) =>
      RuntimeTarget(id: localId, label: label, kind: RuntimeKind.local);

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
