import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';

void main() {
  test('slugifyWorkspacePath matches cursor-agent project slug', () {
    expect(
      CursorWorkspaceTrust.slugifyWorkspacePath(
        '/home/hhoa/Document/testmixed',
      ),
      'home-hhoa-Document-testmixed',
    );
  });

  test('trustMarkerPath is under fake HOME projects dir', () {
    expect(
      CursorWorkspaceTrust.trustMarkerPath(
        '/fake/home',
        '/home/hhoa/Document/testmixed',
      ),
      p.join(
        '/fake/home',
        '.cursor',
        'projects',
        'home-hhoa-Document-testmixed',
        '.workspace-trusted',
      ),
    );
  });

  test('buildTrustMarkerJson includes workspacePath and trustMethod', () {
    final decoded = jsonDecode(
      CursorWorkspaceTrust.buildTrustMarkerJson('/home/hhoa/Document/testmixed'),
    ) as Map<String, Object?>;
    expect(decoded['workspacePath'], '/home/hhoa/Document/testmixed');
    expect(decoded['trustMethod'], CursorWorkspaceTrust.trustMethod);
    expect(decoded['trustedAt'], isNotEmpty);
  });
}
