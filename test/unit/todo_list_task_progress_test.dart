import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/todo_list.dart';

Task _task({
  bool isCompleted = false,
  List<TaskSubItem> subTasks = const [],
}) {
  return Task(
    id: 'task-1',
    title: 'Personal Goal',
    dueDate: DateTime(2026, 7, 20),
    isCompleted: isCompleted,
    subTasks: List<TaskSubItem>.from(subTasks),
  );
}

void main() {
  group('Task progress', () {
    test('flat tasks still score by their completion flag', () {
      expect(taskProgress(_task()), 0);
      expect(taskProgress(_task(isCompleted: true)), 100);
    });

    test('subtasks drive parent progress', () {
      final task = _task(
        subTasks: [
          TaskSubItem(id: 's1', title: 'Drink water', isCompleted: true),
          TaskSubItem(id: 's2', title: 'Walk', isCompleted: false),
        ],
      );

      expect(taskProgress(task), 50);
      expect(taskIsEffectivelyCompleted(task), isFalse);
    });

    test('parent only reaches 100 when every subtask is done', () {
      final task = _task(
        subTasks: [
          TaskSubItem(id: 's1', title: 'Stretch', isCompleted: true),
          TaskSubItem(id: 's2', title: 'Breathe', isCompleted: true),
          TaskSubItem(id: 's3', title: 'Journal', isCompleted: true),
        ],
      );

      expect(taskProgress(task), 100);
      expect(taskIsEffectivelyCompleted(task), isTrue);
    });

    test('syncTaskCompletion clears the parent when subtasks are incomplete',
        () {
      final task = _task(
        isCompleted: true,
        subTasks: [
          TaskSubItem(id: 's1', title: 'One', isCompleted: true),
          TaskSubItem(id: 's2', title: 'Two', isCompleted: false),
        ],
      );

      syncTaskCompletion(task, completedAt: DateTime(2026, 7, 20, 8));

      expect(task.isCompleted, isFalse);
      expect(task.completedAt, isNull);

      task.subTasks[1].isCompleted = true;
      syncTaskCompletion(task, completedAt: DateTime(2026, 7, 20, 9));

      expect(task.isCompleted, isTrue);
      expect(task.completedAt, isNotNull);
    });
  });

  group('Task JSON', () {
    test('round-trips subtasks through JSON', () {
      final original = Task(
        id: 'task-2',
        title: 'Personal Goal',
        description: 'Build the habit step by step',
        dueDate: DateTime(2026, 7, 21),
        tag: TaskTag.personal,
        subTasks: [
          TaskSubItem(
            id: 's1',
            title: 'Plan',
            isCompleted: true,
            createdAt: DateTime(2026, 7, 18),
          ),
          TaskSubItem(
            id: 's2',
            title: 'Do it',
            isCompleted: false,
            createdAt: DateTime(2026, 7, 19),
          ),
        ],
      );

      final json = original.toJson();
      final restored = Task.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.description, original.description);
      expect(restored.tag, original.tag);
      expect(restored.subTasks, hasLength(2));
      expect(restored.subTasks.first.title, 'Plan');
      expect(restored.subTasks.first.isCompleted, isTrue);
      expect(restored.subTasks.last.title, 'Do it');
      expect(restored.subTasks.last.isCompleted, isFalse);
    });
  });
}
