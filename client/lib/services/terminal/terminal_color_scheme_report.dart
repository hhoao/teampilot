import 'dart:typed_data';

/// Removes OSC 997 color-scheme reports (`ESC ] 997 ; n (BEL | ESC \\)`) from an
/// engine→PTY write. Used for CLIs whose TUI mishandles the report (cursor): the
/// embedded terminal answers a mode-2031 subscription with OSC 997, but cursor
/// leaks it into its input box instead of consuming it. The engine emits each
/// report as a single write, so a sequence never straddles two chunks.
Uint8List stripColorSchemeReport(Uint8List data) {
  const esc = 0x1b, bel = 0x07, backslash = 0x5c;
  const marker = [0x1b, 0x5d, 0x39, 0x39, 0x37]; // ESC ] 9 9 7
  if (data.length < marker.length) return data;
  final out = BytesBuilder(copy: false);
  var i = 0;
  while (i < data.length) {
    var isMarker = i + marker.length <= data.length;
    if (isMarker) {
      for (var k = 0; k < marker.length; k++) {
        if (data[i + k] != marker[k]) {
          isMarker = false;
          break;
        }
      }
    }
    if (!isMarker) {
      out.addByte(data[i]);
      i++;
      continue;
    }
    var j = i + marker.length;
    while (j < data.length) {
      final b = data[j];
      if (b == bel) {
        j++;
        break;
      }
      if (b == esc && j + 1 < data.length && data[j + 1] == backslash) {
        j += 2;
        break;
      }
      j++;
    }
    i = j;
  }
  return out.toBytes();
}
