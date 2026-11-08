import 'package:baocode/plan/plan_todos.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plan's to-dos: in its front matter as Cursor keeps them, or in a
/// `## Задачи` section as plans were written before; their statuses; the
/// plan written back with them changed; the message that runs them.
void main() {
  const cursor = '''
---
name: Роадмап после фундамента
overview: "Шесть этапов: staging, рабочее место"
todos:
  - id: stage0-staging
    content: "Этап 0: staging на домене (хостинг, S3)"
    status: completed
  - id: stage1-engine
    content: "Этап 1: ответ движка"
    status: in_progress
  - id: stage1-api
    content: "Этап 1: SSE прогресса"
    status: pending
  - id: stage2-dropped
    content: Отброшено
    status: cancelled
isProject: false
---

# Роадмап: от фундамента к пилоту

Текст плана.
''';

  const legacy = '''
# BaoCode: Cursor's layout

## Context

- [ ] [not-a-task] in another section

```md
## Tasks
- [ ] [fenced] In a code block
```

## Задачи

- [x] [fork-setup] Add the upstream remote
- [ ] [dev-app] The BaoCode Dev app
  - [ ] [nested] Indented, still one
''';

  group('reading', () {
    test("Cursor's: the front matter's to-dos, its title the text's", () {
      final doc = PlanDoc.parse(cursor);
      expect(doc.format, PlanTodosFormat.frontMatter);
      expect(doc.title, 'Роадмап: от фундамента к пилоту');
      expect(doc.overview, 'Шесть этапов: staging, рабочее место');
      expect(
        [for (final todo in doc.todos) todo.id],
        ['stage0-staging', 'stage1-engine', 'stage1-api', 'stage2-dropped'],
      );
      expect(doc.todos.first.text, 'Этап 0: staging на домене (хостинг, S3)');
      expect(
        [for (final todo in doc.todos) todo.state],
        [
          PlanTodoState.completed,
          PlanTodoState.inProgress,
          PlanTodoState.pending,
          PlanTodoState.cancelled,
        ],
      );
      expect(doc.doneCount, 1);
      expect([for (final todo in doc.open) todo.id], ['stage1-api']);
    });

    test('without an H1, its name is the title', () {
      final doc = PlanDoc.parse('---\nname: Just a name\ntodos: []\n---\n');
      expect(doc.title, 'Just a name');
      expect(doc.format, PlanTodosFormat.frontMatter);
      expect(doc.todos, isEmpty);
    });

    test("before: the section's to-dos only", () {
      final doc = PlanDoc.parse(legacy);
      expect(doc.format, PlanTodosFormat.section);
      expect(doc.title, "BaoCode: Cursor's layout");
      expect(
        [for (final todo in doc.todos) todo.id],
        ['fork-setup', 'dev-app', 'nested'],
      );
      expect(doc.todos.first.done, isTrue);
      expect(doc.open, hasLength(2));
    });

    test('## Tasks and ## To-dos are sections too; none, no to-dos', () {
      expect(PlanDoc.parse('## Tasks\n- [ ] [a] A\n').todos.single.id, 'a');
      expect(
        PlanDoc.parse('## To-dos\r\n- [ ] [b] B\r\n').todos.single.text,
        'B',
      );
      final none = PlanDoc.parse('# Just a plan\n\n- [ ] [a] A\n');
      expect(none.format, PlanTodosFormat.none);
      expect(none.hasTodos, isFalse);
    });

    test('front matter that is not YAML: as though there were none', () {
      final doc = PlanDoc.parse('---\ntodos: [oops\n---\n# T\n');
      expect(doc.format, PlanTodosFormat.none);
      expect(doc.title, 'T');
    });
  });

  group('writing', () {
    test('a status changed in the front matter, the rest as it was', () {
      final doc = PlanDoc.parse(cursor);
      final next = doc.withState('stage1-api', PlanTodoState.completed);
      final read = PlanDoc.parse(next);
      expect(read.todos[2].state, PlanTodoState.completed);
      expect(read.todos[0].text, doc.todos[0].text);
      expect(next, contains('name: Роадмап после фундамента'));
      expect(next, contains('isProject: false'));
      expect(
        next,
        endsWith('# Роадмап: от фундамента к пилоту\n\nТекст плана.\n'),
      );
      expect(next.split('\n').length, cursor.split('\n').length);
    });

    test('one added with an id of its words, others removed', () {
      final doc = PlanDoc.parse(cursor);
      final added = PlanDoc.parse(doc.withAdded('Этап 1: SSE прогресса'));
      expect(added.todos.last.id, 'этап-1-sse-прогресса');
      expect(added.todos.last.state, PlanTodoState.pending);
      final again = PlanDoc.parse(added.withAdded('Этап 1: SSE прогресса'));
      expect(again.todos.last.id, 'этап-1-sse-прогресса-2');
      final removed = PlanDoc.parse(
        again.withRemoved({'stage0-staging', 'этап-1-sse-прогресса'}),
      );
      expect(
        [for (final todo in removed.todos) todo.id],
        [
          'stage1-engine',
          'stage1-api',
          'stage2-dropped',
          'этап-1-sse-прогресса-2',
        ],
      );
    });

    test('a plan of before moves its section into front matter made for '
        'it, named after its title', () {
      final doc = PlanDoc.parse(legacy);
      final next = doc.withState('dev-app', PlanTodoState.inProgress);
      final read = PlanDoc.parse(next);
      expect(read.format, PlanTodosFormat.frontMatter);
      expect(next, startsWith('---\nname: "BaoCode: Cursor\'s layout"\n'));
      expect(
        [for (final todo in read.todos) (todo.id, todo.state)],
        [
          ('fork-setup', PlanTodoState.completed),
          ('dev-app', PlanTodoState.inProgress),
          ('nested', PlanTodoState.pending),
        ],
      );
      expect(next, isNot(contains('## Задачи')));
      expect(next, isNot(contains('[dev-app]')));
      expect(next, contains('- [ ] [not-a-task] in another section'));
      expect(next, contains('- [ ] [fenced] In a code block'));
      expect(next, endsWith('```\n'));
    });

    test('a section with front matter already: the to-dos go into it', () {
      const both =
          '---\nname: N\n---\n# T\n\n## Задачи\n\n- [ ] [a] A\n\n'
          '## After\n\nMore.\n';
      final next = PlanDoc.parse(both).withState('a', PlanTodoState.completed);
      expect(
        next,
        '---\nname: N\ntodos:\n  - id: a\n    content: A\n'
        '    status: completed\n---\n# T\n\n## After\n\nMore.\n',
      );
    });

    test('contents with quotes and backslashes read back the same', () {
      final doc = PlanDoc.parse('---\ntodos: []\n---\n');
      const text = r'Say "hi" \ and: more # not a comment';
      expect(PlanDoc.parse(doc.withAdded(text)).todos.single.text, text);
    });
  });

  test('statuses: in progress is running; of the pending ones sent, the '
      'first running while the agent works and none is, the others '
      'queued', () {
    final doc = PlanDoc.parse(cursor);
    Map<String, PlanTodoStatus> of(Set<String> sent, bool streaming) => {
      for (final MapEntry(:key, :value)
          in doc.statuses(sent: sent, streaming: streaming).entries)
        key.id: value,
    };
    expect(of({}, false), {
      'stage0-staging': PlanTodoStatus.done,
      'stage1-engine': PlanTodoStatus.running,
      'stage1-api': PlanTodoStatus.open,
      'stage2-dropped': PlanTodoStatus.cancelled,
    });
    expect(of({'stage1-api'}, true)['stage1-api'], PlanTodoStatus.queued);
    final pending = PlanDoc.parse(
      doc.withState('stage1-engine', PlanTodoState.completed),
    );
    expect(
      pending
          .statuses(sent: {'stage1-api'}, streaming: true)
          .values
          .toList()[2],
      PlanTodoStatus.running,
    );
  });

  test("the message: the command where the agent has it, else Cursor's "
      'words, saying where to mark them', () {
    final doc = PlanDoc.parse(legacy);
    expect(
      PlanRun.message(doc.open, '/plans/p.md', hasCommand: true),
      '/cursor-plan:todos dev-app nested /plans/p.md',
    );
    final words = PlanRun.message(
      doc.open,
      '/plans/p.md',
      hasCommand: false,
      format: PlanTodosFormat.section,
    );
    expect(words, startsWith('Implement the following to-dos from the plan'));
    expect(words, contains('The plan: /plans/p.md'));
    expect(words, contains('change its `- [ ]` to `- [x]`'));
    expect(
      words,
      contains(
        'You have been assigned the following 2 to-dos with IDs: '
        'dev-app, nested',
      ),
    );
    expect(words, contains('1. [dev-app] The BaoCode Dev app'));
    expect(
      PlanRun.message(doc.open.take(1).toList(), 'p', hasCommand: false),
      allOf(
        contains('the following 1 to-do with IDs: dev-app'),
        contains('`status` in its front matter'),
      ),
    );
  });
}
