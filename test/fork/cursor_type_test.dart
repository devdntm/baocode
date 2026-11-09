import 'package:bao_markdown/bao_markdown.dart';
import 'package:baocode/chat/widgets/inline_code.dart';
import 'package:baocode/chat/widgets/markdown_view.dart';
import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:baocode/theme/code_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, String data) => tester.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: MarkdownView(data)),
  ),
);

TextStyle _styleOf(WidgetTester tester, String text) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    TextStyle? found;
    TextStyle? inherited;
    void visit(InlineSpan span, TextStyle? outer) {
      final style = outer?.merge(span.style) ?? span.style;
      if (span is TextSpan) {
        if (span.text == text) found = style;
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      }
    }

    inherited = DefaultTextStyle.of(tester.element(find.byWidget(rich))).style;
    visit(rich.text, inherited);
    if (found != null) return found!;
  }
  throw StateError('no "$text"');
}

void main() {
  tearDown(() => ChatLook.current.value = ChatLook.baocode);

  test('chat.look is cursor only when set so', () {
    expect(ChatLook.parse('cursor'), ChatLook.cursor);
    expect(ChatLook.parse(null), ChatLook.baocode);
    expect(ChatLook.parse('other'), ChatLook.baocode);
  });

  test('the theme tracks text as macOS does, not by Material 3\'s 0.25', () {
    // As Theme.of gives it: the typography's geometry merged in.
    TextTheme shown(ThemeData theme) =>
        ThemeData.localize(theme, theme.typography.englishLike).textTheme;
    expect(shown(buildAppTheme()).bodyMedium!.letterSpacing, 0.25);
    ChatLook.current.value = ChatLook.cursor;
    final cursor = shown(buildAppTheme());
    expect(
      cursor.bodyMedium!.letterSpacing,
      closeTo(CursorType.tracking(14), 1e-9),
    );
    expect(
      cursor.bodySmall!.letterSpacing,
      closeTo(CursorType.tracking(12), 1e-9),
    );
    expect(AppFonts.codeStyle(12).letterSpacing, 0);
  });

  test('a markdown editor\'s style: as before under BaoCode\'s look, as '
      'the chat\'s text under Cursor\'s', () {
    const base = MarkdownEditorStyle(
      text: TextStyle(fontSize: 14, height: 1.65),
    );
    expect(CursorType.markdown(base), same(base));
    ChatLook.current.value = ChatLook.cursor;
    final cursor = CursorType.markdown(base);
    expect(cursor.text.fontSize, CursorType.textSize);
    expect(cursor.text.height, CursorType.textHeight);
    expect(cursor.text.letterSpacing, closeTo(CursorType.tracking(14), 1e-9));
    expect(cursor.heading(2).fontSize, 20);
    expect(cursor.heading(2).fontWeight, FontWeight.w700);
    expect(cursor.bold.fontWeight, FontWeight.w600);
    expect(cursor.codePadding, closeTo(3.6, 1e-9));
    expect(cursor.listGap, CursorType.gap);
    expect(cursor.code.letterSpacing, 0);
    expect(
      cursor.text.merge(cursor.blank).fontSize! *
          cursor.text.merge(cursor.blank).height!,
      closeTo(CursorType.gap, 1e-9),
    );
  });

  testWidgets('BaoCode\'s look stays as upstream\'s', (tester) async {
    await _pump(tester, 'Some **bold** and `code`.');
    expect(MarkdownView.baseStyle.fontSize, 13.5);
    expect(_styleOf(tester, 'bold').fontWeight, FontWeight.w600);
    expect(_styleOf(tester, ' code ').fontSize, CodeFont.uiSized(12.5));
  });

  testWidgets('Cursor\'s: 14 on 22.4, medium bold, code padded by 0.3 em', (
    tester,
  ) async {
    ChatLook.current.value = ChatLook.cursor;
    await _pump(tester, 'Some **bold** and `code`.');
    final text = _styleOf(tester, 'Some ');
    expect(text.fontSize, 14);
    expect(text.height, 1.6);
    expect(text.letterSpacing, closeTo(CursorType.tracking(14), 1e-9));
    final bold = _styleOf(tester, 'bold');
    expect(bold.fontWeight, FontWeight.w500);
    expect(bold.color, AppColors.text);
    final code = _styleOf(tester, 'code');
    expect(code.fontFamily, AppFonts.mono);
    expect(code.letterSpacing, 0);
    expect(code.color, AppColors.text);
    final pad = _styleOf(tester, ' ');
    expect(pad.fontSize, lessThan(code.fontSize!));
    final backdrop = tester.renderObject<RenderInlineCodeBackdrop>(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_InlineCodeBackdrop',
      ),
    );
    expect(backdrop.cursor, isTrue);
    expect(backdrop.color, CursorType.inlineCodeBackground);
  });

  testWidgets('Cursor\'s headings: 16 before, 4 after; paragraphs 10 apart', (
    tester,
  ) async {
    ChatLook.current.value = ChatLook.cursor;
    await _pump(tester, 'One.\n\n## Title\n\nTwo.\n\nThree.');
    final gaps = [
      for (final box in tester.widgetList<SizedBox>(
        find.descendant(
          of: find.byType(MarkdownBlocks),
          matching: find.byType(SizedBox),
        ),
      ))
        if (box.width == null && box.child == null) box.height,
    ];
    expect(gaps, [
      CursorType.headingGapBefore,
      CursorType.headingGapAfter,
      CursorType.gap,
    ]);
  });
}
