import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart';

import 'server_channel.dart';
import 'sftp_filesystem.dart';

/// The SFTP version this server speaks: 3, the only version the fork's
/// client accepts (draft-ietf-secsh-filexfer-02).
const _kSftpVersion = 3;

/// Largest SFTP packet accepted or produced, matching the fork client's
/// limit (`SFTP_MAX_MSG_LENGTH` in OpenSSH terms). The 4-byte length prefix
/// is not counted.
const _kMaxPacketLength = 256 * 1024;

/// Largest read a READ request may ask the filesystem for. A DATA reply
/// carries a 9-byte header (type byte, request id, and the data's 4-byte
/// length prefix) on top of the bytes, so anything past this could never fit
/// one outgoing packet. The requested length is clamped to it in
/// [_SftpServerSession._handleRead] before the filesystem is read: a client
/// may ask for up to a uint32 of bytes, and without the clamp the injected
/// filesystem would materialize that much data only for the outgoing-packet
/// guard in [_SftpServerSession._sendPacket] to discard it — and close the
/// channel.
const _kMaxReadLength = _kMaxPacketLength - 9;

/// Byte budget for a READDIR NAME packet: the encoded payload of the reply
/// (type + request id + count + the names) must stay at or under the
/// [_kMaxPacketLength] limit, because the client destroys the channel on
/// any larger incoming packet. The only way a single entry can exceed the
/// budget on its own is a filename on the order of 128 KiB, which cannot
/// have been created through this server (the client's own requests are
/// under the limit); such an entry would end the listing early rather than
/// kill the channel.
const _kReadDirMaxPacketLength = _kMaxPacketLength;

/// Encoded NAME-packet overhead per entry, used to amortize the per-entry
/// size queries: a name costs its two strings (each a 4-byte length prefix
/// plus the UTF-8 bytes) and its attributes (a flags word, plus whichever
/// optional fields the attrs raise).
const _kNameOverhead = 12;

/// `SSH_FX_FILE_ALREADY_EXISTS`, the SFTPv3 code the fork's
/// [SftpStatusCode] does not name (it stops at 8).
const _sshFxFileAlreadyExists = 11;

/// Serves the SFTPv3 subsystem (draft-ietf-secsh-filexfer-02) on an open
/// session channel over an injected [filesystem].
///
/// Wire format, mirrored from the fork's client: every packet is a 4-byte
/// big-endian length followed by a 1-byte type and the type's payload. The
/// client matches replies to requests by request id, so every reply carries
/// the id of the request it answers. End-of-file and end-of-directory are
/// both reported as a `SSH_FX_EOF` status — the fork's client accepts codes
/// 0 (OK) and 1 (EOF) for every checked operation, and treats an empty DATA
/// chunk as a protocol error, so short regions must be answered with the
/// bytes that exist and a following request with EOF.
///
/// READDIR replies are the one place where the server, not the client,
/// controls a packet's size: a filesystem may hand back a whole directory in
/// one batch, but a NAME packet must stay under the 256 KiB limit or the
/// client destroys the channel. Directory handles therefore buffer the
/// leftover names and serve successive READDIR requests bounded batches;
/// the client's read-until-EOF listdir loop is the protocol's own paging.
///
/// Requests are dispatched as they finish parsing (not one-at-a-time), since
/// the client pipelines reads and writes; every reply is written in a single
/// channel write, so interleaved replies cannot split a packet.
///
/// Unknown or extended request types answer `SSH_FX_OP_UNSUPPORTED`, and
/// filesystem failures map to status codes through the typed
/// [SftpFileSystemException] hierarchy. When the channel ends, every handle
/// still open is released.
Future<void> serveSftpSubsystem(
  SSHServerChannel channel, {
  required SftpFileSystem filesystem,
}) {
  return _SftpServerSession(channel, filesystem).run();
}

class _SftpServerSession {
  _SftpServerSession(this._channel, this._filesystem);

  final SSHServerChannel _channel;
  final SftpFileSystem _filesystem;

  /// Open handles by id, in allocation order. Handle ids are unique per
  /// session, so a stale CLOSE cannot hit a recycled handle.
  final _handles = <int, _SftpHandleEntry>{};
  var _nextHandleId = 0;

  /// Bytes received but not yet parsed into a complete packet.
  Uint8List _pending = Uint8List(0);

  Future<void> run() async {
    final inputEnded = Completer<void>();
    final subscription = _channel.input.listen(
      _onData,
      // The input stream ends not only when the channel finishes (client
      // close, connection teardown) but on the client's bare EOF too — the
      // exit path of a stock OpenSSH sftp client, which sends EOF and then
      // waits for this side to close the channel.
      onDone: inputEnded.complete,
    );
    await inputEnded.future;
    await subscription.cancel();
    await _releaseAllHandles();
    // A no-op when the channel already finished; after a bare client EOF it
    // is what tells the client the subsystem is over.
    _channel.close();
    await _channel.done;
  }

  void _onData(Uint8List data) {
    final builder = BytesBuilder(copy: false)
      ..add(_pending)
      ..add(data);
    _pending = builder.takeBytes();
    _drainPackets();
  }

  /// Extracts every complete packet from [_pending], leaving the remainder
  /// for the next arrival.
  void _drainPackets() {
    while (_pending.length >= 4) {
      final length = ByteData.sublistView(_pending, 0, 4).getUint32(0);
      if (length > _kMaxPacketLength || length < 1) {
        // Same policy the fork's client holds its peer to: an oversized or
        // empty packet is a broken peer, not a recoverable request.
        _channel.printDebug?.call(
          'tp_sshd: closing sftp subsystem: packet length $length is out of '
          'bounds',
        );
        _channel.close();
        return;
      }
      if (_pending.length < 4 + length) return;
      final payload = Uint8List.sublistView(_pending, 4, 4 + length);
      _pending = Uint8List.sublistView(_pending, 4 + length);
      unawaited(_handlePacket(payload));
    }
  }

  Future<void> _handlePacket(Uint8List payload) async {
    final type = payload[0];
    try {
      switch (type) {
        case SftpInitPacket.packetType:
          // No extensions are offered: the fork's client then uses the
          // standard RENAME instead of posix-rename@openssh.com.
          _sendPacket(SftpVersionPacket(_kSftpVersion));
        case SftpOpenPacket.packetType:
          await _handleOpen(SftpOpenPacket.decode(payload));
        case SftpClosePacket.packetType:
          await _handleClose(SftpClosePacket.decode(payload));
        case SftpReadPacket.packetType:
          await _handleRead(SftpReadPacket.decode(payload));
        case SftpWritePacket.packetType:
          await _handleWrite(SftpWritePacket.decode(payload));
        case SftpLStatPacket.packetType:
          final request = SftpLStatPacket.decode(payload);
          await _handleStat(request.requestId, request.path);
        case SftpFStatPacket.packetType:
          await _handleFStat(SftpFStatPacket.decode(payload));
        case SftpSetStatPacket.packetType:
          final request = SftpSetStatPacket.decode(payload);
          // Attribute writes are accepted but not applied: the injected
          // filesystem has no attribute store to write to.
          _sendOk(request.requestId);
        case SftpFSetStatPacket.packetType:
          await _handleFSetStat(SftpFSetStatPacket.decode(payload));
        case SftpOpenDirPacket.packetType:
          await _handleOpenDir(SftpOpenDirPacket.decode(payload));
        case SftpReadDirPacket.packetType:
          await _handleReadDir(SftpReadDirPacket.decode(payload));
        case SftpRemovePacket.packetType:
          final request = SftpRemovePacket.decode(payload);
          await _filesystem.unlink(request.filename);
          _sendOk(request.requestId);
        case SftpMkdirPacket.packetType:
          final request = SftpMkdirPacket.decode(payload);
          await _filesystem.mkdir(request.path, request.attributes);
          _sendOk(request.requestId);
        case SftpRmdirPacket.packetType:
          final request = SftpRmdirPacket.decode(payload);
          await _filesystem.rmdir(request.path);
          _sendOk(request.requestId);
        case SftpRealpathPacket.packetType:
          await _handleRealpath(SftpRealpathPacket.decode(payload));
        case SftpStatPacket.packetType:
          final request = SftpStatPacket.decode(payload);
          await _handleStat(request.requestId, request.path);
        case SftpRenamePacket.packetType:
          final request = SftpRenamePacket.decode(payload);
          await _filesystem.rename(request.oldPath, request.newPath);
          _sendOk(request.requestId);
        case SftpReadlinkPacket.packetType:
        case SftpSymlinkPacket.packetType:
          // The injected filesystem does not model symbolic links.
          _sendStatus(
            _requestIdOf(payload),
            SftpStatusCode.opUnsupported,
            'Symbolic links are not supported',
          );
        case SftpExtendedPacket.packetType:
          _sendStatus(
            SftpExtendedPacket.decode(payload).requestId,
            SftpStatusCode.opUnsupported,
            'Extended requests are not supported',
          );
        default:
          _sendStatus(
            _requestIdOf(payload),
            SftpStatusCode.opUnsupported,
            'Unknown packet type: $type',
          );
      }
    } on Object catch (error) {
      // Every request carries its id right after the type byte; use it so
      // the client's reply matching still resolves after the failure. (INIT
      // has no id and cannot reach here — its handling runs no filesystem
      // call.)
      _sendStatusError(_requestIdOf(payload), error);
    }
  }

  Future<void> _handleOpen(SftpOpenPacket request) async {
    final handle = await _filesystem.openFile(
      request.path,
      _openModeFromFlags(request.flags),
      request.attrs,
    );
    final id = _registerHandle(_SftpHandleEntry.file(request.path, handle));
    _sendPacket(SftpHandlePacket(request.requestId, _encodeHandle(id)));
  }

  Future<void> _handleClose(SftpClosePacket request) async {
    final entry = _removeHandle(request.handle);
    if (entry == null) {
      _sendStatus(request.requestId, SftpStatusCode.failure, 'Invalid handle');
      return;
    }
    // Release first, acknowledge after: the reply is the client's signal
    // that the handle is gone.
    await entry.close();
    _sendOk(request.requestId);
  }

  Future<void> _handleRead(SftpReadPacket request) async {
    final file = _handles[_decodeHandle(request.handle)]?.file;
    if (file == null) {
      _sendStatus(request.requestId, SftpStatusCode.failure, 'Invalid handle');
      return;
    }
    // Clamp before reading: a hostile or careless client may ask for up to a
    // uint32 of bytes, and the filesystem must not be made to materialize
    // more than one reply packet can carry.
    final data = await file.read(
      request.offset,
      math.min(request.length, _kMaxReadLength),
    );
    if (data.isEmpty) {
      // EOF is a status, never an empty DATA packet — the fork's client
      // treats the latter as a protocol error.
      _sendStatus(request.requestId, SftpStatusCode.eof, 'End of file');
    } else {
      _sendPacket(SftpDataPacket(request.requestId, data));
    }
  }

  Future<void> _handleWrite(SftpWritePacket request) async {
    final file = _handles[_decodeHandle(request.handle)]?.file;
    if (file == null) {
      _sendStatus(request.requestId, SftpStatusCode.failure, 'Invalid handle');
      return;
    }
    await file.write(request.offset, request.data);
    _sendOk(request.requestId);
  }

  Future<void> _handleStat(int requestId, String path) async {
    final attrs = await _filesystem.stat(path);
    _sendPacket(SftpAttrsPacket(requestId, attrs));
  }

  Future<void> _handleFStat(SftpFStatPacket request) async {
    final path = _handles[_decodeHandle(request.handle)]?.path;
    if (path == null) {
      _sendStatus(request.requestId, SftpStatusCode.failure, 'Invalid handle');
      return;
    }
    // Both file and directory handles answer FSTAT, off the open path.
    final attrs = await _filesystem.stat(path);
    _sendPacket(SftpAttrsPacket(request.requestId, attrs));
  }

  Future<void> _handleFSetStat(SftpFSetStatPacket request) async {
    if (_handles[_decodeHandle(request.handle)]?.file == null) {
      _sendStatus(request.requestId, SftpStatusCode.failure, 'Invalid handle');
      return;
    }
    // Like SETSTAT: accepted but not applied.
    _sendOk(request.requestId);
  }

  Future<void> _handleOpenDir(SftpOpenDirPacket request) async {
    final listing = await _filesystem.openDir(request.path);
    final id = _registerHandle(
      _SftpHandleEntry.dir(request.path, listing),
    );
    _sendPacket(SftpHandlePacket(request.requestId, _encodeHandle(id)));
  }

  Future<void> _handleReadDir(SftpReadDirPacket request) async {
    final entry = _handles[_decodeHandle(request.handle)];
    final listing = entry?.listing;
    if (listing == null) {
      _sendStatus(request.requestId, SftpStatusCode.failure, 'Invalid handle');
      return;
    }
    // Refill from the listing only once its previous batch is drained: a
    // one-shot listing reports end-of-directory on the refill after its
    // first (possibly whole-directory) batch.
    if (entry!.residualNames.isEmpty) {
      entry.residualNames.addAll(await listing.read());
    }
    final names = entry.takeReadDirBatch();
    if (names.isEmpty) {
      // The fork's client ends its listdir loop on an EOF status.
      _sendStatus(request.requestId, SftpStatusCode.eof, 'End of directory');
    } else {
      _sendPacket(SftpNamePacket(request.requestId, names));
    }
  }

  Future<void> _handleRealpath(SftpRealpathPacket request) async {
    final resolved = await _filesystem.realpath(request.path);
    _sendPacket(
      SftpNamePacket(request.requestId, [
        SftpName(
          filename: resolved,
          longname: resolved,
          attr: SftpFileAttrs(),
        ),
      ]),
    );
  }

  /// Rebuilds an [SftpFileOpenMode] from the wire flags. The fork's class
  /// has no public int constructor, so the mode is folded from its public
  /// constants; SFTPv3 always sets at least one of READ/WRITE, which gives
  /// the fold its base case. Flag bits beyond the six the fork defines are
  /// dropped.
  SftpFileOpenMode _openModeFromFlags(int flags) {
    final staticModes = [
      SftpFileOpenMode.write,
      SftpFileOpenMode.append,
      SftpFileOpenMode.create,
      SftpFileOpenMode.truncate,
      SftpFileOpenMode.exclusive,
    ];
    var mode = (flags & SftpFileOpenMode.read.flag) != 0
        ? SftpFileOpenMode.read
        : SftpFileOpenMode.write;
    for (final staticMode in staticModes) {
      if (flags & staticMode.flag != 0) {
        mode = mode | staticMode;
      }
    }
    return mode;
  }

  int _registerHandle(_SftpHandleEntry entry) {
    final id = _nextHandleId++;
    _handles[id] = entry;
    return id;
  }

  _SftpHandleEntry? _removeHandle(Uint8List handle) {
    final id = _decodeHandle(handle);
    if (id == null) return null;
    return _handles.remove(id);
  }

  Future<void> _releaseAllHandles() async {
    final entries = List.of(_handles.values);
    _handles.clear();
    for (final entry in entries) {
      try {
        await entry.close();
      } on Object catch (error) {
        // Teardown is best effort: one misbehaving handle must not stop the
        // rest from being released.
        _channel.printDebug?.call(
          'tp_sshd: releasing an sftp handle at teardown failed: $error',
        );
      }
    }
  }

  /// The request id of a request payload: the uint32 right after the type
  /// byte, which every request carries (INIT, the one exception, has none).
  int _requestIdOf(Uint8List payload) {
    if (payload.length < 5) return 0;
    return ByteData.sublistView(payload, 1, 5).getUint32(0);
  }

  Uint8List _encodeHandle(int id) {
    final bytes = Uint8List(4);
    ByteData.view(bytes.buffer).setUint32(0, id);
    return bytes;
  }

  int? _decodeHandle(Uint8List handle) {
    if (handle.length != 4) return null;
    return ByteData.sublistView(handle).getUint32(0);
  }

  void _sendOk(int requestId) => _sendStatus(requestId, SftpStatusCode.ok, '');

  void _sendStatus(int requestId, int code, String message) {
    _sendPacket(
      SftpStatusPacket(
        requestId: requestId,
        code: code,
        message: message,
      ),
    );
  }

  /// Maps a filesystem failure onto the wire status code the client sees.
  void _sendStatusError(int requestId, Object error) {
    if (error is SftpNoSuchFileException) {
      _sendStatus(requestId, SftpStatusCode.noSuchFile, error.message);
    } else if (error is SftpPermissionDeniedException) {
      _sendStatus(requestId, SftpStatusCode.permissionDenied, error.message);
    } else if (error is SftpFileExistsException) {
      _sendStatus(requestId, _sshFxFileAlreadyExists, error.message);
    } else {
      _sendStatus(requestId, SftpStatusCode.failure, error.toString());
    }
  }

  void _sendPacket(SftpPacket packet) {
    final payload = packet.encode();
    // The fork's client destroys the channel on any incoming packet over
    // the limit, so shipping an over-limit reply would kill the session on
    // the client's terms — fail it here instead. (READDIR replies are
    // batched down by _handleReadDir; READ replies are clamped to the limit
    // by _handleRead before the filesystem is read.)
    if (payload.length > _kMaxPacketLength) {
      _channel.printDebug?.call(
        'tp_sshd: closing sftp subsystem: outgoing packet of '
        '${payload.length} bytes exceeds the $_kMaxPacketLength byte limit',
      );
      _channel.close();
      return;
    }
    final framed = BytesBuilder(copy: false)
      ..add(_lengthPrefix(payload.length))
      ..add(payload);
    _channel.write(framed.takeBytes());
  }

  Uint8List _lengthPrefix(int length) {
    final bytes = Uint8List(4);
    ByteData.view(bytes.buffer).setUint32(0, length);
    return bytes;
  }
}

/// One open handle: a file or a directory listing, both remembering the path
/// they were opened at (FSTAT answers from it). Directory handles also carry
/// the names a listing batch produced but a single READDIR reply could not
/// fit under the packet limit; the next READDIR drains them first.
class _SftpHandleEntry {
  _SftpHandleEntry.file(this.path, SftpHandle file)
      : file = file,
        listing = null;

  _SftpHandleEntry.dir(this.path, SftpDirListing listing)
      : file = null,
        listing = listing;

  /// The path the handle was opened at.
  final String path;

  /// The open file; `null` for directory handles.
  final SftpHandle? file;

  /// The open directory listing; `null` for file handles.
  final SftpDirListing? listing;

  /// Directory names already read out of [listing] but not yet sent, in
  /// order. Empty for file handles and for drained directories.
  final residualNames = Queue<SftpName>();

  /// Removes and returns the longest prefix of [residualNames] whose NAME
  /// packet stays within the READDIR byte budget.
  List<SftpName> takeReadDirBatch() {
    // type byte + request id + name count.
    const headerLength = 1 + 4 + 4;
    var length = headerLength;
    final batch = <SftpName>[];
    while (residualNames.isNotEmpty) {
      final name = residualNames.first;
      final nameLength =
          _utf8LengthOf(name.filename) + _utf8LengthOf(name.longname);
      final nextLength =
          length + nameLength + _kNameOverhead + _encodedAttrsLength(name.attr);
      if (nextLength > _kReadDirMaxPacketLength) break;
      length = nextLength;
      batch.add(residualNames.removeFirst());
    }
    return batch;
  }

  Future<void> close() =>
      file?.close() ?? listing?.close() ?? Future<void>.value();
}

/// The length of [string] in UTF-8, the encoding the wire uses.
int _utf8LengthOf(String string) => utf8.encode(string).length;

/// The encoded size of [attrs] on the wire: a 4-byte flags word plus
/// whichever optional fields their flag bits raise (size 8, uid/gid 4 + 4,
/// permissions 4, times 4 + 4, plus the extended-pairs block).
int _encodedAttrsLength(SftpFileAttrs attrs) {
  var length = 4;
  if (attrs.size != null) length += 8;
  if (attrs.userID != null && attrs.groupID != null) length += 8;
  if (attrs.mode != null) length += 4;
  if (attrs.accessTime != null && attrs.modifyTime != null) length += 8;
  final extended = attrs.extended;
  if (extended != null) {
    length += 4;
    for (final pair in extended.entries) {
      length += 4 + _utf8LengthOf(pair.key) + 4 + _utf8LengthOf(pair.value);
    }
  }
  return length;
}
