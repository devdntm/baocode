import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/fork/mode_pill.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester) async {
  final session = ChatSession(historyCount: 2);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: ChatScreen(session: session),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() => ChatLook.current.value = ChatLook.baocode);

  testWidgets('the mode as Cursor\'s pill under its look, as before else', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(CursorModePill), findsNothing);
    await tester.pumpWidget(const SizedBox());
    ChatLook.current.value = ChatLook.cursor;
    await _pump(tester);
    expect(find.byType(CursorModePill), findsOneWidget);
    final pill = tester.getSize(find.byType(CursorModePill));
    expect(pill.height, CursorModePill.height);
  });

  test('its fill: fainter at rest than hovered, than open', () {
    final rest = CursorModePill.fill(hovered: false, open: false);
    final hover = CursorModePill.fill(hovered: true, open: false);
    final open = CursorModePill.fill(hovered: false, open: true);
    expect(rest, lessThan(hover));
    expect(hover, lessThan(open));
  });
}
