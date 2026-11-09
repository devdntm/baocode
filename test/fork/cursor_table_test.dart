import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/fork/cursor_table.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 14);

void main() {
  tearDown(() => ChatLook.current.value = ChatLook.baocode);

  test('room to spare: the columns grow to the width by what they hold', () {
    final widths = CursorTable.widths(
      [
        ['Day', 'New'],
        ['7 Nov', '72'],
      ],
      style: _style,
      headStyle: _style,
      width: 600,
    )!;
    expect(widths.reduce((a, b) => a + b), closeTo(600, 0.01));
    expect(widths[0], greaterThan(widths[1]));
  });

  test('too little: each its longest word at least, the rest shared', () {
    final long = List.filled(30, 'word').join(' ');
    final widths = CursorTable.widths(
      [
        ['A', 'B'],
        ['x', long],
      ],
      style: _style,
      headStyle: _style,
      width: 300,
    )!;
    expect(widths.reduce((a, b) => a + b), closeTo(300, 0.01));
    expect(widths[1], greaterThan(widths[0]));
  });

  test('words alone wider than the width: none, the table scrolls', () {
    expect(
      CursorTable.widths(
        [
          [List.filled(40, 'x').join(), List.filled(40, 'y').join()],
        ],
        style: _style,
        headStyle: _style,
        width: 200,
      ),
      isNull,
    );
  });

  testWidgets('under Cursor\'s look a chat\'s table is as wide as the chat, '
      'its cells wrapping; no sideways scroll', (tester) async {
    ChatLook.current.value = ChatLook.cursor;
    final long = List.filled(40, 'word').join(' ');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: MarkdownView('| A | B |\n| - | - |\n| x | $long |\n'),
          ),
        ),
      ),
    );
    final table = tester.getRect(find.byType(Table));
    expect(table.width, closeTo(500 - 2, 1));
    expect(
      find.descendant(
        of: find.byType(MarkdownView),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('BaoCode\'s scrolls as before', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SizedBox(
            width: 500,
            child: MarkdownView('| A | B |\n| - | - |\n| x | y |\n'),
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
  });
}
