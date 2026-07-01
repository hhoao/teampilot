import 'package:mock_anthropic/assigned_task_id_parser.dart';
import 'package:test/test.dart';

void main() {
  test('extracts task id from ASSIGNED TASK tool result text', () {
    const body = {
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'tu_wait_task',
              'content':
                  'ASSIGNED TASK (claimed for you from the shared work queue):\n'
                  '--- 8ba4fa9c-a804-424e-9f91-ab9e2ca62fea [claimed] ---\n'
                  'title: complete-widget',
            },
          ],
        },
      ],
    };

    expect(
      extractAssignedTaskIdFromAnthropicRequest(body),
      '8ba4fa9c-a804-424e-9f91-ab9e2ca62fea',
    );
  });

  test('returns null when no ASSIGNED TASK is present', () {
    expect(
      extractAssignedTaskIdFromAnthropicRequest({'messages': []}),
      isNull,
    );
  });
}
