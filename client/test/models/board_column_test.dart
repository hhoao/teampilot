import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/board_column.dart';
import 'package:teampilot/services/team_bus/tasks/team_task.dart';

void main() {
  group('BoardColumn', () {
    test('maps each TaskStatus to a lane', () {
      expect(BoardColumnMapping.forStatus(TaskStatus.pending), BoardColumn.pending);
      expect(BoardColumnMapping.forStatus(TaskStatus.claimed), BoardColumn.claimed);
      expect(BoardColumnMapping.forStatus(TaskStatus.done), BoardColumn.done);
      expect(BoardColumnMapping.forStatus(TaskStatus.failed), BoardColumn.done);
      expect(BoardColumnMapping.forStatus(TaskStatus.cancelled), BoardColumn.done);
    });

    test('statusesFor round-trips every status into exactly one column', () {
      for (final s in TaskStatus.values) {
        final col = BoardColumnMapping.forStatus(s);
        expect(BoardColumnMapping.statusesFor(col), contains(s));
      }
      // every column is non-empty
      for (final c in BoardColumn.values) {
        expect(BoardColumnMapping.statusesFor(c), isNotEmpty);
      }
    });

    test('pending and claimed columns hold exactly one status', () {
      expect(BoardColumnMapping.statusesFor(BoardColumn.pending),
          [TaskStatus.pending]);
      expect(BoardColumnMapping.statusesFor(BoardColumn.claimed),
          [TaskStatus.claimed]);
    });
  });
}
