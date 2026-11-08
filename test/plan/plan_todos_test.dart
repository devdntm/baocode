import 'package:baocode/plan/plan_todos.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plan's to-dos, as the cursor-plan rules write them, their statuses,
/// and the message that runs them.
void main() {
  const plan = '''
# BaoCode: Cursor's layout

## Context

- [ ] [not-a-task] in another section

## Задачи

- [x] [fork-setup] Add the upstream remote
- [ ] [dev-app] The BaoCode Dev app
* [X] [layout] The setting
- [ ] no id, not a to-do
  - [ ] [nested] Indented, still one

```md
## Tasks
- [ ] [fenced] In a code block
```

## Проверка

- [ ] [after] Past the section
''';

  test('reads the title and the section\'s to-dos only', () {
    final todos = PlanTodos.parse(plan);
    expect(todos.title, "BaoCode: Cursor's layout");
    expect(todos.hasSection, isTrue);
    expect(
      [for (final todo in todos.todos) todo.id],
      ['fork-setup', 'dev-app', 'layout', 'nested'],
    );
    expect(todos.todos.first.text, 'Add the upstream remote');
    expect(
      [for (final todo in todos.todos) todo.done],
      [true, false, true, false],
    );
    expect(todos.doneCount, 2);
    expect([for (final todo in todos.open) todo.id], ['dev-app', 'nested']);
    expect(todos.todos[1].line, 9);
  });

  test('## Tasks and ## To-dos are sections too; none, no section', () {
    expect(PlanTodos.parse('## Tasks\n- [ ] [a] A\n').todos.single.id, 'a');
    expect(
      PlanTodos.parse('## To-dos\r\n- [ ] [b] B\r\n').todos.single.text,
      'B',
    );
    expect(PlanTodos.parse('## todos\n- [ ] [c] C\n').todos, hasLength(1));
    final none = PlanTodos.parse('# Just a plan\n\n- [ ] [a] A\n');
    expect(none.hasSection, isFalse);
    expect(none.todos, isEmpty);
    expect(none.title, 'Just a plan');
  });

  test('statuses: done ticked; of those sent, the first running while the '
      'agent works, the others queued', () {
    final todos = PlanTodos.parse(plan);
    Map<String, PlanTodoStatus> of(Set<String> sent, bool streaming) => {
      for (final MapEntry(:key, :value)
          in todos.statuses(sent: sent, streaming: streaming).entries)
        key.id: value,
    };
    expect(of({}, false), {
      'fork-setup': PlanTodoStatus.done,
      'dev-app': PlanTodoStatus.open,
      'layout': PlanTodoStatus.done,
      'nested': PlanTodoStatus.open,
    });
    expect(of({'fork-setup', 'dev-app', 'nested'}, true), {
      'fork-setup': PlanTodoStatus.done,
      'dev-app': PlanTodoStatus.running,
      'layout': PlanTodoStatus.done,
      'nested': PlanTodoStatus.queued,
    });
    expect(of({'dev-app', 'nested'}, false)['dev-app'], PlanTodoStatus.queued);
  });

  test('a box ticked and unticked, nothing else changed', () {
    final todos = PlanTodos.parse(plan);
    final devApp = todos.todos[1];
    final ticked = setPlanTodoDone(plan, devApp, done: true);
    expect(ticked, plan.replaceFirst('- [ ] [dev-app]', '- [x] [dev-app]'));
    expect(PlanTodos.parse(ticked).todos[1].done, isTrue);
    final nested = todos.todos[3];
    expect(
      setPlanTodoDone(plan, nested, done: true),
      plan.replaceFirst('  - [ ] [nested]', '  - [x] [nested]'),
    );
    expect(
      setPlanTodoDone(plan, todos.todos.first, done: false),
      plan.replaceFirst('- [x] [fork-setup]', '- [ ] [fork-setup]'),
    );
    // Its line is another's now: left as it is.
    expect(
      setPlanTodoDone('- [ ] [other] X\n', devApp, done: true),
      '- [ ] [other] X\n',
    );
  });

  test('the message: the command where the agent has it, else Cursor\'s '
      'words', () {
    final todos = PlanTodos.parse(plan).open;
    expect(
      PlanRun.message(todos, '/plans/p.md', hasCommand: true),
      '/cursor-plan:todos dev-app nested /plans/p.md',
    );
    final words = PlanRun.message(todos, '/plans/p.md', hasCommand: false);
    expect(words, startsWith('Implement the following to-dos from the plan'));
    expect(words, contains('The plan: /plans/p.md'));
    expect(
      words,
      contains(
        'You have been assigned the following 2 to-dos with IDs: '
        'dev-app, nested',
      ),
    );
    expect(words, contains('1. [dev-app] The BaoCode Dev app'));
    expect(words, contains('2. [nested] Indented, still one'));
    expect(words, contains("Don't stop until you have completed"));
    expect(
      PlanRun.message(todos.take(1).toList(), 'p', hasCommand: false),
      contains('the following 1 to-do with IDs: dev-app'),
    );
  });
}
