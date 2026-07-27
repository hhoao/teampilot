import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/subagent_preview_controller.dart';

void main() {
  test('push pop prune', () {
    final c = SubagentPreviewController();
    c.push('a');
    c.push('b');
    expect(c.stack, ['a', 'b']);
    c.pop();
    expect(c.stack, ['a']);
    c.pruneToAvailable({'b'}); // a missing → clear or drop to empty
    expect(c.stack, isEmpty);
    c.push('b');
    c.pruneToAvailable({'b'});
    expect(c.stack, ['b']);
  });

  test('push pop clear notify; prune is silent', () {
    final c = SubagentPreviewController();
    var notified = 0;
    c.addListener(() => notified++);

    c.push('a');
    c.push('b');
    expect(notified, 2);

    c.pop();
    expect(notified, 3);

    notified = 0;
    c.pruneToAvailable({'a'}); // keeps ['a'] — still silent even if unchanged
    expect(c.stack, ['a']);
    expect(notified, 0);

    c.push('x');
    c.push('y');
    notified = 0;
    c.pruneToAvailable({'a'}); // drop from first missing → keep ['a']
    expect(c.stack, ['a']);
    expect(notified, 0);

    c.clear();
    expect(c.stack, isEmpty);
    expect(notified, 1);
  });
}
