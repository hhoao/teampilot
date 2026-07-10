/// Converts between Dart `String` UTF-16 code-unit offsets and the UTF-8
/// byte offsets tree-sitter works in. Needed because astral code points
/// (e.g. emoji) are 2 UTF-16 code units but up to 4 UTF-8 bytes, and BMP
/// code points outside ASCII (e.g. CJK) are 1 code unit but 2-3 bytes.
class Utf8IndexMap {
  Utf8IndexMap(this.text) : _byteOffsetByCodeUnit = _buildByteOffsets(text);

  String text;
  List<int> _byteOffsetByCodeUnit;

  /// Total UTF-8 byte length of [text].
  int get byteLength => _byteOffsetByCodeUnit.last;

  /// The UTF-8 byte offset corresponding to a UTF-16 code-unit offset
  /// `0 <= codeUnitOffset <= text.length`.
  ///
  /// A `codeUnitOffset` that splits a surrogate pair has no well-defined
  /// byte boundary; it maps to the byte offset of the start of that pair.
  int byteOffsetForCodeUnit(int codeUnitOffset) {
    return _byteOffsetByCodeUnit[codeUnitOffset];
  }

  /// The UTF-16 code-unit offset corresponding to a UTF-8 byte offset
  /// `0 <= byteOffset <= byteLength`. Tree-sitter offsets are always on
  /// rune boundaries, so an exact match is expected; a non-boundary
  /// [byteOffset] resolves to the nearest code unit at or after it.
  int codeUnitOffsetForByte(int byteOffset) {
    var low = 0;
    var high = _byteOffsetByCodeUnit.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_byteOffsetByCodeUnit[mid] < byteOffset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Applies a code-unit range replace to [text] and rebuilds the offset
  /// table. This is a full rebuild (O(n)), not an incremental patch — kept
  /// simple until profiling shows it matters for large files.
  void applyEdit({
    required int codeUnitStart,
    required int codeUnitDeleteCount,
    required String insert,
  }) {
    text = text.replaceRange(
      codeUnitStart,
      codeUnitStart + codeUnitDeleteCount,
      insert,
    );
    _byteOffsetByCodeUnit = _buildByteOffsets(text);
  }

  static const int _highSurrogateStart = 0xD800;
  static const int _highSurrogateEnd = 0xDBFF;
  static const int _lowSurrogateStart = 0xDC00;
  static const int _lowSurrogateEnd = 0xDFFF;

  static List<int> _buildByteOffsets(String text) {
    final codeUnits = text.codeUnits;
    final byteOffsets = List<int>.filled(codeUnits.length + 1, 0);
    var byteOffset = 0;
    var i = 0;
    while (i < codeUnits.length) {
      final unit = codeUnits[i];
      final isHighSurrogate =
          unit >= _highSurrogateStart && unit <= _highSurrogateEnd;
      final hasLowSurrogate =
          i + 1 < codeUnits.length &&
          codeUnits[i + 1] >= _lowSurrogateStart &&
          codeUnits[i + 1] <= _lowSurrogateEnd;
      if (isHighSurrogate && hasLowSurrogate) {
        final codePoint =
            0x10000 +
            (unit - _highSurrogateStart) * 0x400 +
            (codeUnits[i + 1] - _lowSurrogateStart);
        byteOffsets[i] = byteOffset;
        byteOffsets[i + 1] = byteOffset; // mid-pair: no valid boundary here
        byteOffset += _utf8ByteLength(codePoint);
        byteOffsets[i + 2] = byteOffset;
        i += 2;
      } else {
        byteOffsets[i] = byteOffset;
        byteOffset += _utf8ByteLength(unit);
        byteOffsets[i + 1] = byteOffset;
        i += 1;
      }
    }
    return byteOffsets;
  }

  static int _utf8ByteLength(int codePoint) {
    if (codePoint <= 0x7F) return 1;
    if (codePoint <= 0x7FF) return 2;
    if (codePoint <= 0xFFFF) return 3;
    return 4;
  }
}
