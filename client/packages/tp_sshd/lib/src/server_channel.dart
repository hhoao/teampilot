import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart';

/// Upper bound of a window after an adjustment (RFC 4254 §5.2: a uint32).
const _maximumWindow = 0xffffffff;

/// One open channel on the server side. Owns window accounting in both
/// directions and the data/EOF/close lifecycle of the channel.
///
/// Instances are created by [SSHServerConnection] when a client opens a
/// channel; the connection then drives them through [handleWindowAdjust],
/// [handleData], [handleExtendedData], [handleEof], [handleClose] and
/// [handleRequest] as the client's messages arrive.
class SSHServerChannel {
  /// The receive-window size the server grants on every channel it opens:
  /// 2 MiB, the same generous default typical servers (including OpenSSH)
  /// hand out, so a client is never throttled before it gets going.
  static const initialReceiveWindow = 2 * 1024 * 1024;

  /// The largest channel packet the server accepts from the peer and the
  /// largest it sends: RFC 4253 §6.1's 32768 payload bytes every
  /// implementation must accept.
  static const maximumPacketSize = 32768;

  SSHServerChannel({
    required this.recipientChannel,
    required this.ourChannel,
    required this.channelType,
    required int peerInitialWindowSize,
    required int peerMaximumPacketSize,
    required void Function(Uint8List payload) sendPacket,
    required void Function(SSHServerChannel channel) onClosed,
    void Function(String description)? onProtocolViolation,
    this.closeFlushTimeout = const Duration(seconds: 2),
    this.printDebug,
  })  : _sendWindow = peerInitialWindowSize,
        // A peer advertising a zero maximum packet size could never be sent
        // anything; fall back to the protocol minimum rather than stall
        // forever.
        _maximumOutgoingPacketSize = peerMaximumPacketSize > 0
            ? peerMaximumPacketSize
            : maximumPacketSize,
        _sendPacket = sendPacket,
        _onProtocolViolation = onProtocolViolation,
        _onClosed = onClosed;

  /// The channel number the client assigned to this channel. Every message
  /// the server sends on it addresses the client by this id.
  final int recipientChannel;

  /// The channel number this server assigned. Every message the client
  /// sends on the channel addresses the server by this id.
  final int ourChannel;

  /// The channel type as requested by the client (`'session'`).
  final String channelType;

  /// How long [close] waits for the client to grant the window credit that
  /// data still queued for it needs, before the tail is dropped and the
  /// channel finished anyway. Two seconds: generous for a healthy peer
  /// granting window, short enough not to hold channels open against a
  /// stalled one.
  final Duration closeFlushTimeout;

  final void Function(Uint8List payload) _sendPacket;
  final void Function(SSHServerChannel channel) _onClosed;

  /// Reports a channel-protocol violation that must take the whole
  /// connection down (the receive window being overrun past its grace
  /// margin): the connection turns the description into a
  /// `DISCONNECT(2, …)`.
  final void Function(String description)? _onProtocolViolation;
  final void Function(String? message)? printDebug;

  /// Remaining bytes the client may still send us (the receive direction).
  var _receiveWindow = initialReceiveWindow;

  /// Bytes the client has sent past the granted receive window so far, not
  /// reset by an in-window packet — sshd's `local_window_exceeded`
  /// (channels.c:channel_input_data): the first overage is tolerated, and
  /// once the total excess crosses a tenth of the window the peer is
  /// ignoring flow control and the connection goes down.
  var _windowExceeded = 0;

  /// Bytes admitted onto [input]/[extendedInput] that the consumer has not
  /// reported through [consumeInput] yet. Never re-granted while it sits
  /// here: against a non-reading program the window stays a bound.
  var _pendingInput = 0;

  /// Bytes the consumer reported as consumed but not yet granted back.
  var _consumedInput = 0;

  /// Remaining bytes we may still send the client (the send direction).
  int _sendWindow;

  /// The packet-size limit the client gave for data we send it.
  final int _maximumOutgoingPacketSize;

  final _input = StreamController<Uint8List>();
  final _extendedInput = StreamController<Uint8List>();

  /// Outgoing chunks waiting for send-window credit.
  final _outgoing = Queue<_OutgoingChunk>();

  final _done = Completer<void>();

  var _sentEof = false;

  /// EOF requested via [sendEof] but still behind queued data; sent when
  /// the queue drains (no data may follow an EOF, RFC 4254 §5.3).
  var _eofPending = false;

  var _receivedEof = false;
  var _sentClose = false;

  /// The client has sent CHANNEL_CLOSE: from its point of view the channel
  /// is over, so no further message for this id can be a race against our
  /// own close. Reported through [onClosed] so the connection can tell a
  /// fully reaped channel id (messages for it are a protocol error, the way
  /// sshd treats a freed channel) from one this server closed but the
  /// client has not acknowledged yet (in-flight messages are tolerated).
  var _receivedClose = false;

  /// Whether the client has already sent CHANNEL_CLOSE.
  bool get receivedClose => _receivedClose;

  /// [close] was called while data was still queued for window credit: the
  /// channel finishes itself once the queue drains, or when the bounded wait
  /// in [closeFlushTimeout] gives up on the client's window.
  var _closePending = false;

  /// The give-up timer behind a pending close.
  Timer? _closeFlushTimer;

  /// Data the client sends on this channel.
  Stream<Uint8List> get input => _input.stream;

  /// Extended data (stderr) the client sends on this channel.
  Stream<Uint8List> get extendedInput => _extendedInput.stream;

  /// Completes when the channel is closed in both directions, or torn down
  /// together with the connection.
  Future<void> get done => _done.future;

  /// Whether this channel is finished: no more data flows either way.
  bool get isClosed => _done.isCompleted;

  /// Whether the client has already sent EOF (no more input will arrive).
  bool get receivedEof => _receivedEof;

  /// Hook invoked when the client sends a channel request (e.g. `exec`,
  /// `shell`) on this channel, with the request that triggered it — so the
  /// request cannot go stale between concurrent dispatches.
  ///
  /// The hook reports the request's outcome through the returned future:
  /// `true` acknowledges it (CHANNEL_SUCCESS reply when the client asked for
  /// one), `false` — or a thrown error — refuses it (CHANNEL_FAILURE). The
  /// reply is sent the moment the future settles; a hook that keeps serving
  /// the channel afterwards (streaming output, exit-status, close) must let
  /// the future settle first, or the reply is never sent. A channel with no
  /// hook refuses every request.
  Future<bool> Function(
      SSHServerChannel channel, SSH_Message_Channel_Request request)? onRequest;

  /// Sends [data] to the client as channel data (stdout).
  ///
  /// Data is chunked to the client's maximum packet size; whatever the
  /// client's current window does not cover is queued and flushed as
  /// window adjustments arrive. Data offered after [sendEof] or [close] is
  /// dropped (with a debug log).
  void write(Uint8List data) => _enqueueOutgoing(data, null);

  /// Sends [data] to the client as extended channel data (stderr). See
  /// [write] for the chunking, window and EOF semantics.
  void writeExtended(Uint8List data) => _enqueueOutgoing(
        data,
        SSH_Message_Channel_Extended_Data.dataTypeStderr,
      );

  /// Tells the client no more data will be sent on this channel.
  ///
  /// The EOF follows any data still queued for window credit; further
  /// [write]/[writeExtended] calls are dropped.
  void sendEof() {
    if (isClosed || _sentEof || _eofPending) return;
    _flushOutgoing();
    if (_outgoing.isNotEmpty) {
      _eofPending = true;
      return;
    }
    _sendEof();
  }

  /// Closes the channel: sends EOF (after flushing what the client's window
  /// allows) and then CHANNEL_CLOSE, finishing the channel from our side.
  ///
  /// Data still queued for window credit gets a bounded chance to go out:
  /// [closeFlushTimeout] for the client to grant the credit the tail needs,
  /// after which the channel finishes anyway and the rest is dropped. A
  /// window that opens in time flushes the whole queue first, so an exec's
  /// output tail is not truncated by a merely slow peer.
  void close() {
    if (isClosed || _closePending) return;
    _flushOutgoing();
    if (_outgoing.isEmpty) {
      if (!_sentEof) {
        _sendEof();
      }
      _finish();
      return;
    }
    _closePending = true;
    _closeFlushTimer = Timer(closeFlushTimeout, () {
      _closeFlushTimer = null;
      if (isClosed) return;
      printDebug?.call(
        'tp_sshd: dropping ${_outgoing.length} queued outgoing chunks on '
        'channel $ourChannel after the close flush bound '
        '($closeFlushTimeout) expired',
      );
      if (!_sentEof) {
        _sendEof();
      }
      _finish();
    });
  }

  /// Applies a window adjustment from the client: grows the send window and
  /// flushes whatever data was stalled on it.
  void handleWindowAdjust(int bytesToAdd) {
    if (isClosed) return;
    if (bytesToAdd < 0 || _sendWindow + bytesToAdd > _maximumWindow) {
      _failChannel(
        'window adjustment of $bytesToAdd on top of $_sendWindow exceeds '
        'the maximum window',
      );
      return;
    }
    _sendWindow += bytesToAdd;
    _flushOutgoing();
  }

  /// Delivers channel data received from the client.
  void handleData(Uint8List data) => _handleIncoming(data, _input);

  /// Delivers extended channel data received from the client. All extended
  /// data is surfaced on [extendedInput]; SSH defines only stderr (type 1).
  void handleExtendedData(int dataTypeCode, Uint8List data) =>
      _handleIncoming(data, _extendedInput);

  /// Records the client's EOF: no more input will arrive.
  void handleEof() {
    if (isClosed || _receivedEof) return;
    _receivedEof = true;
    _closeInputStreams();
  }

  /// Records the client's CHANNEL_CLOSE: the channel is finished. Our own
  /// CHANNEL_CLOSE is echoed if it was not sent yet.
  void handleClose() {
    _receivedClose = true;
    _finish();
  }

  /// Dispatches a channel request from the client to [onRequest]. See there
  /// for the acknowledge/refuse semantics.
  void handleRequest(SSH_Message_Channel_Request request) {
    if (isClosed) return;
    final handler = onRequest;
    if (handler == null) {
      _replyToRequest(request, accepted: false);
      return;
    }
    unawaited(() async {
      var accepted = false;
      try {
        accepted = await handler(this, request);
      } on Object {
        accepted = false;
      }
      _replyToRequest(request, accepted: accepted);
    }());
  }

  /// Sends an `exit-status` channel request (RFC 4254 §6.10): the exit
  /// status of the process this channel ran. The client never replies to it.
  ///
  /// Must be sent before [sendEof] and [close] — it is the channel's last
  /// word on what its process did, and a client that sees EOF first may stop
  /// waiting for it.
  void sendExitStatus(int exitStatus) {
    if (isClosed) return;
    _sendPacket(
      SSH_Message_Channel_Request.exitStatus(
        recipientChannel: recipientChannel,
        exitStatus: exitStatus,
      ).encode(),
    );
  }

  /// Tears the channel down without sending anything: the connection's
  /// transport is gone. Called by [SSHServerConnection], not by embedders.
  void detach() {
    if (isClosed) return;
    _closeFlushTimer?.cancel();
    _closeFlushTimer = null;
    _outgoing.clear();
    _closeInputStreams();
    _done.complete();
  }

  void _enqueueOutgoing(Uint8List data, int? dataTypeCode) {
    if (isClosed || _sentEof || _eofPending || _closePending) {
      printDebug?.call(
        'tp_sshd: dropping ${data.length} outgoing bytes on channel '
        '$ourChannel after EOF/close',
      );
      return;
    }
    if (data.isEmpty) return;
    _outgoing.add(_OutgoingChunk(data, dataTypeCode));
    _flushOutgoing();
  }

  /// Sends as much queued data as the client's window and packet size
  /// allow. A window of zero stalls (returns with the queue intact) until
  /// [handleWindowAdjust] unblocks it.
  void _flushOutgoing() {
    while (_outgoing.isNotEmpty) {
      if (_sendWindow <= 0) return;
      final chunk = _outgoing.first;
      final take = min(
        chunk.bytes.length,
        min(_sendWindow, _maximumOutgoingPacketSize),
      );
      final data = Uint8List.sublistView(chunk.bytes, 0, take);
      if (chunk.dataTypeCode == null) {
        _sendPacket(
          SSH_Message_Channel_Data(
            recipientChannel: recipientChannel,
            data: data,
          ).encode(),
        );
      } else {
        _sendPacket(
          SSH_Message_Channel_Extended_Data(
            recipientChannel: recipientChannel,
            dataTypeCode: chunk.dataTypeCode!,
            data: data,
          ).encode(),
        );
      }
      _sendWindow -= take;
      if (take == chunk.bytes.length) {
        _outgoing.removeFirst();
      } else {
        _outgoing.removeFirst();
        _outgoing.addFirst(
          _OutgoingChunk(
            Uint8List.sublistView(chunk.bytes, take),
            chunk.dataTypeCode,
          ),
        );
      }
    }
    if (_eofPending && !_sentEof) {
      _sendEof();
    }
    // A close waiting on this queue draining has just been satisfied: the
    // whole tail went out, so the channel can finish cleanly.
    if (_closePending && _outgoing.isEmpty && !isClosed) {
      _closeFlushTimer?.cancel();
      _closeFlushTimer = null;
      if (!_sentEof) {
        _sendEof();
      }
      _finish();
    }
  }

  void _sendEof() {
    _eofPending = false;
    _sentEof = true;
    _sendPacket(
      SSH_Message_Channel_EOF(recipientChannel: recipientChannel).encode(),
    );
  }

  /// Admits one inbound data message: checks it against the packet size and
  /// window the client was given, surfaces it on [controller], and holds
  /// the credit back until the consumer reports it through [consumeInput].
  void _handleIncoming(Uint8List data, StreamController<Uint8List> controller) {
    if (isClosed || data.isEmpty) return;
    if (_receivedEof) {
      if (identical(controller, _extendedInput)) {
        // Extended data after the client's CHANNEL_EOF is NOT tolerated
        // the way plain data is: sshd fatals — "Received extended_data
        // after EOF on channel %d." (channels.c:
        // channel_input_extended_data's CHAN_EOF_RCVD branch, the other
        // half of audit D01's citation) — because stderr cannot be
        // fake-consumed into the (closed) stdin stream either. Same
        // violation path as a peer ignoring the channel window (F4/F5).
        _onProtocolViolation?.call(
          'Received extended_data after EOF on channel $ourChannel.',
        );
        return;
      }
      // Data after the client's CHANNEL_EOF on a live channel: sshd
      // fake-consumes it — window accounting only, the bytes dropped
      // (channels.c:channel_input_data's post-EOF branch). Throwing here
      // instead (the input controller is closed) would tear down the whole
      // connection over one misbehaving channel (audit D01).
      printDebug?.call(
        'tp_sshd: dropping ${data.length} bytes on channel $ourChannel '
        'after the client EOF',
      );
      _pendingInput += data.length;
      consumeInput(data.length);
      return;
    }
    if (data.length > maximumPacketSize) {
      // The documented C04 divergence: a chunk over the advertised
      // maximumPacketSize fails this channel (sshd drops it silently).
      _failChannel(
        'the client sent ${data.length} bytes, over the packet-size bound it '
        'was given',
      );
      return;
    }
    if (data.length > _receiveWindow) {
      // Past the granted window (channels.c:channel_input_data): the first
      // overages are tolerated — the data is still admitted and the credit
      // zeroed — but the excess accumulates, and past a tenth of the window
      // the peer is ignoring flow control and the connection goes down
      // (audit A16 + C05).
      final excess = data.length - _receiveWindow;
      _windowExceeded += excess;
      printDebug?.call(
        'tp_sshd: channel $ourChannel rcvd too much data ${data.length}, '
        'window $_receiveWindow/$initialReceiveWindow '
        '(excess total $_windowExceeded)',
      );
      _receiveWindow = 0;
      if (_windowExceeded > initialReceiveWindow ~/ 10) {
        _onProtocolViolation?.call(
          'channel $ourChannel: peer ignored channel window',
        );
        return;
      }
    } else {
      _receiveWindow -= data.length;
      _windowExceeded = 0;
    }
    _pendingInput += data.length;
    controller.add(data);
  }

  /// Reports [bytes] of the channel's input as consumed by its reader: the
  /// program took them off its stdin (or the SFTP server parsed them, the
  /// forward pump handed them to the socket). Only consumed bytes are ever
  /// granted back, which is what makes the advertised receive window a
  /// bound — against a non-reading program no credit returns and a peer
  /// that keeps sending is disconnected by [_handleIncoming] (F4, audit
  /// A16 + C05; sshd's channel_check_window grants `local_consumed` only).
  ///
  /// The grant waits for one of sshd's two refill thresholds — the window
  /// below half, or more than three maximum-size packets outstanding — so
  /// interactive channels stay quiet while bulk transfers refill early.
  void consumeInput(int bytes) {
    if (isClosed || bytes <= 0) return;
    final admitted = bytes < _pendingInput ? bytes : _pendingInput;
    if (admitted <= 0) return;
    _pendingInput -= admitted;
    _consumedInput += admitted;
    final outstanding = initialReceiveWindow - _receiveWindow;
    final belowHalf = _receiveWindow < initialReceiveWindow ~/ 2;
    final threePacketsOutstanding = outstanding > 3 * maximumPacketSize;
    if (!belowHalf && !threePacketsOutstanding) return;
    _receiveWindow += _consumedInput;
    _sendPacket(
      SSH_Message_Channel_Window_Adjust(
        recipientChannel: recipientChannel,
        bytesToAdd: _consumedInput,
      ).encode(),
    );
    _consumedInput = 0;
  }

  void _replyToRequest(
    SSH_Message_Channel_Request request, {
    required bool accepted,
  }) {
    if (!request.wantReply || isClosed) return;
    _sendPacket(
      (accepted
              ? SSH_Message_Channel_Success(recipientChannel: recipientChannel)
              : SSH_Message_Channel_Failure(recipientChannel: recipientChannel))
          .encode(),
    );
  }

  /// Sends CHANNEL_CLOSE (unless already sent) and tears the channel down
  /// locally. Data still queued for the client's window is dropped.
  void _finish() {
    if (isClosed) return;
    _closeFlushTimer?.cancel();
    _closeFlushTimer = null;
    if (!_sentClose) {
      _sentClose = true;
      _sendPacket(
        SSH_Message_Channel_Close(recipientChannel: recipientChannel).encode(),
      );
    }
    _outgoing.clear();
    _closeInputStreams();
    _done.complete();
    _onClosed(this);
  }

  /// Closes this channel after the client violated the channel protocol,
  /// leaving the rest of the connection untouched (mirroring the fork's
  /// client-side policy).
  void _failChannel(String reason) {
    printDebug?.call(
      'tp_sshd: closing channel $ourChannel ($channelType): $reason',
    );
    _finish();
  }

  void _closeInputStreams() {
    if (!_input.isClosed) unawaited(_input.close());
    if (!_extendedInput.isClosed) unawaited(_extendedInput.close());
  }
}

/// One queued outgoing payload, waiting for send-window credit.
class _OutgoingChunk {
  const _OutgoingChunk(this.bytes, this.dataTypeCode);

  final Uint8List bytes;

  /// The extended-data type code, or `null` for plain channel data.
  final int? dataTypeCode;
}
