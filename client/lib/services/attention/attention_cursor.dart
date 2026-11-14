import 'attention_event.dart';

/// Highest `seq` a client has consumed for one authority epoch.
final class AttentionCursor {
  const AttentionCursor({
    required this.authorityId,
    required this.epoch,
    required this.seq,
  });

  final String authorityId;
  final int epoch;
  final int seq;

  AttentionCursor advance(AttentionEvent event) {
    if (event.authorityId != authorityId) {
      return AttentionCursor(
        authorityId: event.authorityId,
        epoch: event.epoch,
        seq: event.seq,
      );
    }
    // A stale (older-epoch) event must never rewind the cursor.
    if (event.epoch < epoch) return this;
    if (event.epoch > epoch) {
      return AttentionCursor(
        authorityId: event.authorityId,
        epoch: event.epoch,
        seq: event.seq,
      );
    }
    if (event.seq <= seq) return this;
    return AttentionCursor(
      authorityId: authorityId,
      epoch: epoch,
      seq: event.seq,
    );
  }

  Map<String, Object?> toJson() => {
    'authorityId': authorityId,
    'epoch': epoch,
    'seq': seq,
  };

  static AttentionCursor? fromJson(Object? json) {
    if (json is! Map) return null;
    final authorityId = json['authorityId'];
    final epoch = json['epoch'];
    final seq = json['seq'];
    if (authorityId is! String || authorityId.isEmpty) return null;
    if (epoch is! num || epoch <= 0) return null;
    if (seq is! num || seq < 0) return null;
    return AttentionCursor(
      authorityId: authorityId,
      epoch: epoch.toInt(),
      seq: seq.toInt(),
    );
  }
}
