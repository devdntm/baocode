import 'dart:async';

import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/widgets/plan_start.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/kernel_types.dart';
import 'package:baocode/plan/plan_build.dart';
import 'package:baocode/plan/plan_sessions.dart';
import 'package:baocode/plan/plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A kernel fed [events], that keeps what it is sent and whether it was
/// told to start building.
class _Kernel implements AgentKernel, StartsPlans {
  _Kernel(this.descriptor, this.events);

  @override
  final KernelDescriptor descriptor;
  @override
  final Stream<KernelEvent> events;
  final List<KernelTurn> sent = [];
  var building = false;

  @override
  void send(KernelTurn turn) => sent.add(turn);

  @override
  void startBuilding() => building = true;

  @override
  KernelHealth get health => KernelHealth.idle;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

(ChatSession, _Kernel, StreamController<KernelEvent>) _session() {
  final live = StreamController<KernelEvent>.broadcast(sync: true);
  addTearDown(live.close);
  late final KernelDescriptor descriptor;
  late final _Kernel kernel;
  descriptor = KernelDescriptor(
    id: 'test',
    label: 'Test',
    icon: Icons.abc,
    description: '',
    create: (context) => kernel = _Kernel(descriptor, live.stream),
  );
  final session = ChatSession(
    kernel: descriptor,
    kernels: [descriptor],
    kernelContext: const KernelContext(cwd: '/p'),
    historyCount: 0,
  );
  addTearDown(session.dispose);
  return (session, kernel, live);
}

const _path = '/home/me/.claude/plans/p.md';

const _plan = '''
---
todos:
  - id: one
    content: The first
    status: completed
  - id: two
    content: The second
    status: pending
---

# P
''';

void main() {
  setUp(() {
    PlanFiles.read = (path) async => path == _path ? _plan : null;
    PlanFiles.modified = null;
  });
  tearDown(() {
    PlanSessions.created = null;
    PlanFiles.forgetSent();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Material(child: Center(child: child)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  final build = find.byKey(const ValueKey('plan.build'));

  testWidgets('awaiting the user, Build starts the plan with its open '
      'to-dos to do', (tester) async {
    final (session, kernel, live) = _session();
    live.add(
      const ItemUpserted(
        1,
        'plan',
        PlanItem(path: _path, round: 1, status: PlanStatus.awaiting),
      ),
    );
    await pump(tester, PlanStartBar(session: session, path: _path));
    expect(find.byType(PlanBuildBar), findsOneWidget);
    await tester.tap(build);
    await tester.pump();
    expect(kernel.building, isTrue);
    expect(kernel.sent.single.text, contains('1. [two] The second'));
    expect(kernel.sent.single.text, isNot(contains('[one]')));
  });

  testWidgets('started, Build has the open ones done in the conversation; '
      'its arrow, in a new agent', (tester) async {
    final (session, kernel, _) = _session();
    final (fresh, freshKernel, _) = _session();
    PlanSessions.created = (path, {folder}) => fresh;
    await pump(
      tester,
      PlanStartBar(session: session, path: _path, maxPickerWidth: 180),
    );
    await tester.tap(build);
    await tester.pump();
    expect(kernel.building, isFalse);
    expect(kernel.sent.single.text, contains('1. [two] The second'));

    await tester.tap(find.byKey(const ValueKey('plan.build.more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build in New Agent'));
    await tester.pumpAndSettle();
    expect(freshKernel.sent.single.text, contains('1. [two] The second'));
  });

  testWidgets('on a plan\'s card in the history: only while it awaits', (
    tester,
  ) async {
    final (session, _, _) = _session();
    await pump(tester, PlanStartBar(session: session, path: _path));
    expect(build, findsNothing);
  });

  testWidgets('another file\'s bar is as it was', (tester) async {
    final (session, _, _) = _session();
    await pump(tester, PlanStartBar(session: session, path: '/p/notes.md'));
    expect(find.byType(PlanBuildBar), findsNothing);
  });
}
