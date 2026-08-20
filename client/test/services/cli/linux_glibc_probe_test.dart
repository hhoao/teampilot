import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/installer/linux_glibc_probe.dart';

void main() {
  test('parses GLIBC=major.minor from probe stdout', () {
    expect(LinuxGlibcProbe.parse('GLIBC=2.17\n'), (major: 2, minor: 17));
    expect(LinuxGlibcProbe.parse('noise\nGLIBC=2.31\n'), (major: 2, minor: 31));
    expect(LinuxGlibcProbe.parse('GLIBC=unknown\n'), isNull);
    expect(LinuxGlibcProbe.parse('TERMUX=0\n'), isNull);
  });

  test('cursor-agent requires glibc 2.28', () {
    expect(LinuxGlibcProbe.isBelowCursorMinimum('GLIBC=2.17\n'), isTrue);
    expect(LinuxGlibcProbe.isBelowCursorMinimum('GLIBC=2.27\n'), isTrue);
    expect(LinuxGlibcProbe.isBelowCursorMinimum('GLIBC=2.28\n'), isFalse);
    expect(LinuxGlibcProbe.isBelowCursorMinimum('GLIBC=2.31\n'), isFalse);
    expect(LinuxGlibcProbe.isBelowCursorMinimum('GLIBC=unknown\n'), isFalse);
  });

  test('probe script prints GLIBC= from ldd', () {
    expect(LinuxGlibcProbe.probeScript(), contains('ldd --version'));
    expect(LinuxGlibcProbe.probeScript(), contains("printf 'GLIBC="));
  });
}
