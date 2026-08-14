import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/subagent_preview_controller.dart';

void main() {
  test('push pop prune', () {
    final c = SubagentPreviewController();
    c.push('a');
    c.push('b');
    expect(c.stack, ['a', 'b']);
    c.popAndStopFollow();
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

    c.popAndStopFollow();
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

  test('computeAutoFollow: pref off / follow stopped / duplicates', () {
    final c = SubagentPreviewController();

    // pref 关闭 → 不自动开
    expect(
      c.computeAutoFollow(
        prefEnabled: false,
        runningIds: ['task-1'],
        availableIds: {'task-1'},
      ),
      isNull,
    );

    // pref 开启 + running 且 attachment 可用 → 返回最新 running id
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-new', 'task-old'],
        availableIds: {'task-new', 'task-old'},
      ),
      'task-new',
    );
    c.autoOpen('task-new');
    expect(c.stack, ['task-new']);

    // 已打开的 id 不重复返回
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-new'],
        availableIds: {'task-new'},
      ),
      isNull,
    );

    // attachment 尚未膨胀 → 跳过(等到 available 后再弹)
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-2'],
        availableIds: const {},
      ),
      isNull,
    );
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-2'],
        availableIds: {'task-2'},
      ),
      'task-2',
    );
  });

  test('popAndStopFollow: nested pop keeps follow; back to parent stops it', () {
    final c = SubagentPreviewController();
    c.autoOpen('task-1');
    c.push('nested');
    c.popAndStopFollow(); // 嵌套层 → 仍在预览内
    expect(c.stack, ['task-1']);
    expect(c.followStopped, isFalse);

    c.popAndStopFollow(); // 回到父会话 → 停止跟随
    expect(c.stack, isEmpty);
    expect(c.followStopped, isTrue);

    // followStopped 后同一/其他子 agent 都不再自动开
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-2'],
        availableIds: {'task-2'},
      ),
      isNull,
    );

    // resetFollow(会话切换)解除
    c.resetFollow();
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-2'],
        availableIds: {'task-2'},
      ),
      'task-2',
    );
  });

  test('clear resets follow state', () {
    final c = SubagentPreviewController();
    c.autoOpen('task-1');
    c.popAndStopFollow();
    expect(c.followStopped, isTrue);
    c.clear();
    expect(c.followStopped, isFalse);
    expect(
      c.computeAutoFollow(
        prefEnabled: true,
        runningIds: ['task-1'],
        availableIds: {'task-1'},
      ),
      'task-1',
    );
  });
}
