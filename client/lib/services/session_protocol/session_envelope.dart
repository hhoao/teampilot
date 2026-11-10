/// Protocol version carried in every envelope.
const sessionProtocolVersion = 1;

/// Logical channels multiplexed on one byte stream.
enum SessionChannel { control, state, content, attention, bulk }

/// Message type names. Unknown names are ignored unless they arrive on the
/// control channel, where the receiver answers `error` instead of silently
/// dropping a command.
abstract final class SessionMessageType {
  static const hello = 'hello';
  static const helloAck = 'helloAck';
  static const attach = 'attach';
  static const snapshot = 'snapshot';
  static const delta = 'delta';
  static const content = 'content';
  static const contentDelta = 'contentDelta';
  static const contentAck = 'contentAck';
  static const sessionList = 'sessionList';
  static const intent = 'intent';
  static const intentResult = 'intentResult';
  static const attention = 'attention';
  static const attentionAck = 'attentionAck';
  static const resync = 'resync';
  static const ping = 'ping';
  static const pong = 'pong';
  static const error = 'error';
}

/// Versioned envelope: `{v, ch, type, seq, ack, corr, body}`.
final class SessionEnvelope {
  const SessionEnvelope({
    required this.type,
    required this.channel,
    this.seq = 0,
    this.ack = 0,
    this.corr = '',
    this.body = const {},
    this.proto = sessionProtocolVersion,
  });

  final int proto;
  final String type;
  final SessionChannel channel;
  final int seq;
  final int ack;
  final String corr;
  final Map<String, Object?> body;

  SessionEnvelope copyWith({
    String? type,
    SessionChannel? channel,
    int? seq,
    int? ack,
    String? corr,
    Map<String, Object?>? body,
  }) => SessionEnvelope(
    proto: proto,
    type: type ?? this.type,
    channel: channel ?? this.channel,
    seq: seq ?? this.seq,
    ack: ack ?? this.ack,
    corr: corr ?? this.corr,
    body: body ?? this.body,
  );

  Map<String, Object?> toJson() => {
    'v': proto,
    'ch': channel.name,
    'type': type,
    'seq': seq,
    'ack': ack,
    if (corr.isNotEmpty) 'corr': corr,
    'body': body,
  };

  static SessionEnvelope? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['v'];
    if (version is num && version.toInt() != sessionProtocolVersion) {
      return null;
    }
    final type = json['type'];
    if (type is! String || type.isEmpty) return null;
    final channel = _channel(json['ch']);
    final seq = json['seq'];
    final ack = json['ack'];
    final corr = json['corr'];
    final body = json['body'];
    return SessionEnvelope(
      proto: version is num ? version.toInt() : sessionProtocolVersion,
      type: type,
      channel: channel,
      seq: seq is num ? seq.toInt() : 0,
      ack: ack is num ? ack.toInt() : 0,
      corr: corr is String ? corr : '',
      body: body is Map
          ? {
              for (final entry in body.entries)
                entry.key.toString(): entry.value,
            }
          : const {},
    );
  }

  static SessionChannel _channel(Object? raw) {
    final name = raw is String ? raw : '';
    for (final channel in SessionChannel.values) {
      if (channel.name == name) return channel;
    }
    return SessionChannel.control;
  }
}
