import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/plan/plan_sessions.dart';
import 'package:baocode/plan/plan_todos.dart';
import 'package:baocode/plan/plan_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A kernel that keeps what it is sent, with the cursor-plan:todos command
/// where [skill].
class _Kernel implements AgentKernel, ProvidesCommands {
  _Kernel(this.descriptor, {required this.skill});

  @override
  final KernelDescriptor descriptor;
  final bool skill;
  final List<KernelTurn> sent = [];

  @override
  Stream<KernelEvent> get events => const Stream.empty();

  @override
  List<KernelCommand> get commands => [
    if (skill)
      const KernelCommand('cursor-plan:todos', 'Run to-dos', Icons.checklist),
  ];

  @override
  void send(KernelTurn turn) => sent.add(turn);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

(ChatSession, _Kernel) _session({bool skill = false}) {
  late final KernelDescriptor descriptor;
  late final _Kernel kernel;
  descriptor = KernelDescriptor(
    id: 'test',
    label: 'Test',
    icon: Icons.abc,
    description: '',
    create: (context) => kernel = _Kernel(descriptor, skill: skill),
  );
  final session = ChatSession(
    kernel: descriptor,
    kernels: [descriptor],
    kernelContext: const KernelContext(cwd: '/p'),
    historyCount: 0,
  );
  addTearDown(session.dispose);
  return (session, kernel);
}

const _path = '/home/me/.claude/plans/p.md';

const _cursor = '''
---
name: Grow the input
todos:
  - id: one
    content: The first
    status: completed
  - id: two
    content: The second
    status: pending
  - id: three
    content: The third
    status: pending
  - id: four
    content: Dropped
    status: cancelled
isProject: false
---

# Grow the input
''';

void main() {
  late Map<String, String> files;
  setUp(() {
    files = {};
    PlanFiles.read = (path) async => files[path];
    PlanFiles.write = (path, text) async => files[path] = text;
    PlanFiles.modified = null;
    PlanTodosBlock.pollEvery = const Duration(milliseconds: 50);
  });
  tearDown(() {
    PlanTodosBlock.pollEvery = const Duration(seconds: 1);
    PlanSessions.of = null;
    PlanSessions.created = null;
    PlanFiles.forgetSent();
  });

  Future<void> pump(WidgetTester tester, {ChatSession? session}) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PlanContext(
            session: session,
            child: const SingleChildScrollView(
              child: PlanTodosBlock(path: _path),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder row(String id) => find.byKey(ValueKey(('plan.todo', id)));
  Finder heading() => find.byKey(const ValueKey('plan.todos.heading'));
  String headingText(WidgetTester tester) =>
      tester.widget<Text>(heading()).data!;

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    return gesture;
  }

  testWidgets('"N To-dos", each to-do\'s words, no ids', (tester) async {
    files[_path] = _cursor;
    final (session, _) = _session();
    await pump(tester, session: session);
    expect(headingText(tester), '4 To-dos');
    for (final text in ['The first', 'The second', 'The third', 'Dropped']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('two'), findsNothing);
    expect(
      tester.widget<Text>(find.text('The first')).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      tester.widget<Text>(find.text('Dropped')).style?.decoration,
      TextDecoration.lineThrough,
    );
  });

  testWidgets('without to-dos, nothing', (tester) async {
    files[_path] = '# Just a plan\n';
    await pump(tester);
    expect(heading(), findsNothing);
  });

  testWidgets('one run from its row by the command where the agent has '
      'it', (tester) async {
    files[_path] = _cursor;
    final (session, kernel) = _session(skill: true);
    await pump(tester, session: session);
    final gesture = await mouse(tester);
    await gesture.moveTo(tester.getCenter(row('three')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: row('three'),
        matching: find.byKey(const ValueKey('plan.todo.run')),
      ),
    );
    await tester.pump();
    expect(kernel.sent.single.text, '/cursor-plan:todos three $_path');
  });

  testWidgets('picked by a click: "N To-dos Selected", built in a new agent '
      'in Cursor\'s words; cleared by the cross', (tester) async {
    files[_path] = _cursor;
    final (session, _) = _session();
    final (fresh, freshKernel) = _session();
    final made = <String>[];
    PlanSessions.created = (path, {folder}) {
      made.add(path);
      return fresh;
    };
    await pump(tester, session: session);
    await tester.tap(find.text('The second'));
    await tester.pump();
    expect(headingText(tester), '1 To-do Selected');
    await tester.tap(find.byKey(const ValueKey('plan.todos.unselect')));
    await tester.pump();
    expect(headingText(tester), '4 To-dos');

    await tester.tap(find.text('The second'));
    await tester.pump();
    await tester.tap(find.text('The third'));
    await tester.pump();
    expect(headingText(tester), '2 To-dos Selected');
    expect(find.byKey(const ValueKey('plan.todo.picked')), findsNWidgets(2));
    // Done and dropped ones are not picked.
    await tester.tap(find.text('The first'));
    await tester.pump();
    expect(headingText(tester), '2 To-dos Selected');

    await tester.tap(find.byKey(const ValueKey('plan.todos.buildNew')));
    await tester.pump();
    expect(made, [_path]);
    final words = freshKernel.sent.single.text;
    expect(words, startsWith('Implement the following to-dos from the plan'));
    expect(words, contains('1. [two] The second'));
    expect(words, contains('2. [three] The third'));
    expect(words, contains('`status` in its front matter'));
    expect(headingText(tester), '4 To-dos');
  });

  testWidgets('its menu sets its status in the file; New adds one', (
    tester,
  ) async {
    files[_path] = _cursor;
    final (session, _) = _session();
    await pump(tester, session: session);
    await tester.tap(find.text('The second'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(
      PlanDoc.parse(files[_path]!).todos[1].state,
      PlanTodoState.completed,
    );
    expect(
      tester.widget<Text>(find.text('The second')).style?.decoration,
      TextDecoration.lineThrough,
    );

    await tester.tap(find.byKey(const ValueKey('plan.todos.new')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('plan.todos.newInput')),
      'A fifth',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(PlanDoc.parse(files[_path]!).todos.last.text, 'A fifth');
    expect(find.text('A fifth'), findsOneWidget);
    expect(headingText(tester), '5 To-dos');
  });

  testWidgets('a plan of before: its section\'s to-dos, moved into front '
      'matter as one is changed', (tester) async {
    files[_path] = '# Old\n\nText.\n\n## Задачи\n\n- [x] [a] Done one\n- [ ] [b] Open one\n';
    final (session, _) = _session();
    await pump(tester, session: session);
    expect(headingText(tester), '2 To-dos');
    await tester.tap(find.text('Open one'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelled').last);
    await tester.pumpAndSettle();
    final written = files[_path]!;
    expect(written, startsWith('---\nname: Old\ntodos:\n'));
    expect(written, isNot(contains('## Задачи')));
    expect(written, endsWith('# Old\n\nText.\n'));
    expect(PlanDoc.parse(written).todos[1].state, PlanTodoState.cancelled);
  });

  testWidgets('read again as the agent marks one', (tester) async {
    files[_path] = _cursor;
    final (session, _) = _session();
    await pump(tester, session: session);
    files[_path] = _cursor.replaceFirst(
      'content: The second\n    status: pending',
      'content: The second\n    status: in_progress',
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(
      find.descendant(
        of: row('two'),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'IdeSpinning',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('in the IDE, the conversation the app says: one made in the '
      'folder to run in', (tester) async {
    files[_path] = _cursor;
    final (session, kernel) = _session();
    final asked = <(String, String?, bool)>[];
    PlanSessions.of = (path, {folder, required create}) {
      asked.add((path, folder, create));
      return create ? session : null;
    };
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: PlanContext(
            folder: '/p',
            child: SingleChildScrollView(child: PlanTodosBlock(path: _path)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(asked.first, (_path, '/p', false));
    final gesture = await mouse(tester);
    await gesture.moveTo(tester.getCenter(row('two')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: row('two'),
        matching: find.byKey(const ValueKey('plan.todo.run')),
      ),
    );
    await tester.pump();
    expect(asked, contains((_path, '/p', true)));
    expect(kernel.sent.single.text, contains('1. [two] The second'));
  });
}
