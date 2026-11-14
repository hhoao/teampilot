import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('parses root, idle timeout, and repeated cli ids', () {
    final parsed = parseAcpProxyArgs(const [
      '--root',
      '/tmp/tp',
      '--idle-timeout',
      '30m',
      '--cli',
      'claude',
      '--cli',
      'codex',
    ]);

    expect(parsed.root.path, Directory('/tmp/tp').path);
    expect(parsed.idleTimeout, const Duration(minutes: 30));
    expect(parsed.detach, isFalse);
    expect(parsed.cliIds, ['claude', 'codex']);
  });

  test('missing --root throws FormatException', () {
    expect(() => parseAcpProxyArgs(const []), throwsFormatException);
    expect(
      () => parseAcpProxyArgs(const ['--cli', 'claude', '--detach']),
      throwsFormatException,
    );
  });

  test('--detach is true only when present', () {
    final plain = parseAcpProxyArgs(const ['--root', '/tmp/tp']);
    expect(plain.detach, isFalse);
    expect(plain.idleTimeout, acpProxyIdleTimeout);
    expect(plain.cliIds, isEmpty);

    final detached = parseAcpProxyArgs(const [
      '--detach',
      '--root',
      '/tmp/tp',
      '--cli',
      'claude',
    ]);
    expect(detached.detach, isTrue);
    expect(detached.root.path, Directory('/tmp/tp').path);
    expect(detached.cliIds, ['claude']);
  });
}
