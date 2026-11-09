import 'package:baocode/fork/checkpoints.dart';
import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, VoidCallback? onRestore) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: CheckpointHover(
              onRestore: onRestore,
              child: const SizedBox(width: 200, height: 40, child: Text('hi')),
            ),
          ),
        ),
      ),
    );

void main() {
  tearDown(() => ChatLook.current.value = ChatLook.baocode);

  testWidgets('under BaoCode\'s look, none', (tester) async {
    await _pump(tester, () {});
    expect(find.bySemanticsLabel('Restore checkpoint'), findsNothing);
  });

  testWidgets('Cursor\'s: shown while the pointer is over the message; '
      'asked, then restored', (tester) async {
    ChatLook.current.value = ChatLook.cursor;
    var restored = 0;
    await _pump(tester, () => restored++);
    final link = find.bySemanticsLabel('Restore checkpoint');
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: link, matching: find.byType(Visibility)).first,
          )
          .visible,
      isFalse,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('hi')));
    addTearDown(mouse.removePointer);
    await tester.pump();
    expect(
      tester
          .widget<Visibility>(
            find.ancestor(of: link, matching: find.byType(Visibility)).first,
          )
          .visible,
      isTrue,
    );

    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(restored, 0);

    await mouse.moveTo(tester.getCenter(find.text('hi')));
    await tester.pump();
    await tester.tap(link);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(restored, 1);
  });

  testWidgets('no checkpoint, no link', (tester) async {
    ChatLook.current.value = ChatLook.cursor;
    await _pump(tester, null);
    expect(find.bySemanticsLabel('Restore checkpoint'), findsNothing);
  });
}
