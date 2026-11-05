import 'package:equatable/equatable.dart';

enum VaultReferenceKind { sshProfile, appProvider, managedProvider, github }

class VaultReference extends Equatable {
  const VaultReference({
    required this.kind,
    required this.id,
    required this.label,
  });

  final VaultReferenceKind kind;
  final String id;
  final String label;

  @override
  List<Object?> get props => [kind, id, label];
}
