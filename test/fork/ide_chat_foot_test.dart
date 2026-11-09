import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/chat/widgets/context_meter.dart';
import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester) async {
  final session = ChatSession(historyCount: 4);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: ChatScreen(
        session: session,
        embedded: true,
        below: const Text('main*'),
      ),
    ),
  );
  await tester.pump();
}

Finder _inComposer(Finder finder) =>
    find.descendant(of: find.byType(ChatComposer), matching: finder);

void main() {
  tearDown(() => ChatLook.current.value = ChatLook.baocode);

  testWidgets('BaoCode\'s IDE chat: the branch under the input, the ring in '
      'it', (tester) async {
    await _pump(tester);
    expect(find.text('main*'), findsOneWidget);
    expect(_inComposer(find.byType(ContextMeter)), findsOneWidget);
  });

  testWidgets('Cursor\'s: the branch and the labelled meter under the input', (
    tester,
  ) async {
    ChatLook.current.value = ChatLook.cursor;
    await _pump(tester);
    expect(find.text('main*'), findsOneWidget);
    expect(_inComposer(find.byType(ContextMeter)), findsNothing);
    final meter = tester.widget<ContextMeter>(find.byType(ContextMeter));
    expect(meter.labeled, isTrue);
    // Both under the input, on one row.
    final composer = tester.getRect(find.byType(ChatComposer));
    final branch = tester.getRect(find.text('main*'));
    final ring = tester.getRect(find.byType(ContextMeter));
    expect(branch.top, greaterThanOrEqualTo(composer.bottom));
    expect(ring.center.dy, closeTo(branch.center.dy, 4));
    expect(ring.left, greaterThan(branch.right));
  });
}
