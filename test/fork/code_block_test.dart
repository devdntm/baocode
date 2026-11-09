import 'package:baocode/chat/widgets/code_citation.dart';
import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(),
    home: const Scaffold(
      body: MarkdownCodeBlock(code: 'docker logs app', language: 'bash'),
    ),
  ),
);

BoxDecoration _card(WidgetTester tester) =>
    tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(MarkdownCodeBlock),
                matching: find.byType(Container),
              ),
            )
            .first
            .decoration!
        as BoxDecoration;

void main() {
  tearDown(() => ChatLook.current.value = ChatLook.baocode);

  testWidgets('BaoCode\'s: a title with the language, a filled card', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('bash'), findsOneWidget);
    expect(find.byIcon(Codicons.chevronDown), findsOneWidget);
  });

  testWidgets('Cursor\'s: no title, on the conversation, a faint edge', (
    tester,
  ) async {
    ChatLook.current.value = ChatLook.cursor;
    await _pump(tester);
    expect(find.text('bash'), findsNothing);
    expect(find.byIcon(Codicons.chevronDown), findsNothing);
    final card = _card(tester);
    expect(card.color, const Color(0x00000000));
    expect(card.borderRadius, BorderRadius.circular(10));
    expect(find.textContaining('docker logs app'), findsOneWidget);
  });
}
