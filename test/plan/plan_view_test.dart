import 'dart:async';

import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/plan/plan_sessions.dart';
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

const _plan = '''
# Grow the input

## Задачи

- [x] [one] The first
- [ ] [two] The second
- [ ] [three] The third
''';

const _body = Key('plan-body');

void main() {
  setUp(() => PlanView.pollEvery = const Duration(milliseconds: 50));
  tearDown(() {
    PlanView.pollEvery = const Duration(seconds: 1);
    PlanSessions.of = null;
    PlanView.forgetSent();
  });

  Future<void> pump(
    WidgetTester tester, {
    ChatSession? session,
    String? folder,
    required String Function() text,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: PlanView(
            path: _path,
            session: session,
            folder: folder,
            read: (_) async => text(),
            body: const SizedBox.expand(key: _body),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder row(String id) => find.byKey(ValueKey(('plan.todo', id)));

  testWidgets('its title, how many are done, its to-dos over the plan', (
    tester,
  ) async {
    final (session, _) = _session();
    await pump(tester, session: session, text: () => _plan);
    expect(find.text('Grow the input'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);
    for (final text in ['The first', 'The second', 'The third']) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.byKey(_body), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(_body)).dy,
      greaterThan(tester.getBottomLeft(row('three')).dy),
    );
    expect(find.byKey(const ValueKey('plan.runAll')), findsOneWidget);
  });

  testWidgets('without a section of to-dos, the plan alone', (tester) async {
    final (session, _) = _session();
    await pump(tester, session: session, text: () => '# Just a plan\n');
    expect(find.byKey(_body), findsOneWidget);
    expect(find.text('Just a plan'), findsNothing);
    expect(find.byKey(const ValueKey('plan.runAll')), findsNothing);
  });

  testWidgets('Run all sends the open ones by the command where the agent '
      'has it; they are queued, the first running as it works', (tester) async {
    final (session, kernel) = _session(skill: true);
    await pump(tester, session: session, text: () => _plan);
    await tester.tap(find.byKey(const ValueKey('plan.runAll')));
    await tester.pump();
    expect(kernel.sent.single.text, '/cursor-plan:todos two three $_path');
    // Sent, both wait their turn; nothing to run again.
    expect(find.byKey(const ValueKey('plan.runAll')), findsNothing);
    expect(
      find.descendant(of: row('two'), matching: find.byType(Tooltip)),
      findsNothing,
    );
  });

  testWidgets('one run on its own, in Cursor\'s words where the agent has '
      'no command; several picked, Run selected', (tester) async {
    final (session, kernel) = _session();
    await pump(tester, session: session, text: () => _plan);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(row('three')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: row('three'),
        matching: find.byKey(const ValueKey('plan.todo.run')),
      ),
    );
    await tester.pump();
    final words = kernel.sent.single.text;
    expect(words, startsWith('Implement the following to-dos from the plan'));
    expect(words, contains('1. [three] The third'));
    expect(words, isNot(contains('[two]')));

    // The other one picked by its box.
    await gesture.moveTo(tester.getCenter(row('two')));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: row('two'),
        matching: find.byKey(const ValueKey('plan.todo.select')),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plan.runSelected')));
    await tester.pump();
    expect(kernel.sent, hasLength(2));
    expect(kernel.sent.last.text, contains('1. [two] The second'));
  });

  testWidgets('read again as the agent ticks one', (tester) async {
    final (session, _) = _session();
    var text = _plan;
    await pump(tester, session: session, text: () => text);
    expect(find.text('1 of 3'), findsOneWidget);
    text = _plan.replaceFirst('- [ ] [two]', '- [x] [two]');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('in the IDE, the conversation the app says: none to run in '
      'but one to make in the folder', (tester) async {
    final (session, kernel) = _session();
    final asked = <(String, String?, bool)>[];
    PlanSessions.of = (path, {folder, required create}) {
      asked.add((path, folder, create));
      return create ? session : null;
    };
    await pump(tester, folder: '/p', text: () => _plan);
    expect(asked.first, (_path, '/p', false));
    await tester.tap(find.byKey(const ValueKey('plan.runAll')));
    await tester.pump();
    expect(asked, contains((_path, '/p', true)));
    expect(kernel.sent.single.text, contains('[two] The second'));
  });
}
