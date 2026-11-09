import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/fork/browser/browser_contribution.dart';
import 'package:baocode/fork/browser/browser_mirror.dart';
import 'package:baocode/fork/browser/fork_browser.dart';
import 'package:baocode/fork/cursor_look.dart';
import 'package:baocode/ide/file_views.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => ChatLook.current.value = ChatLook.baocode);

  test('not offered without Cursor\'s look or a browser connected', () {
    expect(ForkBrowser.offered, isFalse);
    ChatLook.current.value = ChatLook.cursor;
    // No browser has connected under test.
    expect(ForkBrowser.offered, isFalse);
  });

  test('the side panel shows the changes for its page while not offered', () {
    final tabs = SidePanelTabs()..section = SidePanelSection.browser;
    expect(tabs.shown, SidePanelSection.changes);
    expect(tabs.current, isNull);
  });

  test('the IDE opens its path as the page, no file read', () {
    ForkBrowserContribution.registerView();
    final view = FileViews.of(ForkBrowser.idePath);
    expect(view?.id, 'fork.browser');
    expect(FileViews.of('/project/Browser'), isNull);
  });

  test('an agent in the browser opens the page once a turn, only where '
      'it is offered', () async {
    final started = <Object>[];
    final sub = ForkBrowser.started.listen(started.add);
    addTearDown(sub.cancel);
    final session = Object();
    // Not offered under test (no browser connected): nothing opens.
    ForkBrowser.agentInBrowser(session);
    await Future<void>.delayed(Duration.zero);
    expect(started, isEmpty);
    ForkBrowser.turnEnded(session);
  });

  testWidgets('the page says no browser is connected, under test', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: BrowserMirror()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('No browser is connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
