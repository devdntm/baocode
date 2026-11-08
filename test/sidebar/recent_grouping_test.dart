import 'package:baocode/main.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fork's grouping by recency (pinned, today, the last 7 and 30 days,
/// older), chosen in the chat's sidebar; and the sidebar of one project's
/// chats, as the IDE's Cursor layout lists them.
void main() {
  Finder inSidebar(Finder finder) =>
      find.descendant(of: find.byType(Sidebar), matching: finder);

  AgentThread named(Workspace workspace, String title) =>
      workspace.threads.firstWhere((thread) => thread.title == title);

  /// One unpinned agent in each of the groups.
  void spread(Workspace workspace) {
    final now = DateTime.now();
    named(workspace, 'Rate limit per API key').updatedAt = now;
    named(workspace, 'Edit sent messages in history').updatedAt = now.subtract(
      const Duration(days: 4),
    );
    named(workspace, 'Translate rules guide to Chinese').updatedAt = now
        .subtract(const Duration(days: 20));
    named(workspace, 'Flaky integration test on CI').updatedAt = now.subtract(
      const Duration(days: 60),
    );
  }

  Future<Workspace> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = Workspace.mock();
    await tester.pumpWidget(BaoCodeApp(workspace: workspace));
    await tester.pump();
    return workspace;
  }

  testWidgets('By … has Recent: pinned, today, the last 7 and 30 days, '
      'older; the others as they were', (tester) async {
    final workspace = await pumpApp(tester);
    spread(workspace);
    await tester.tap(inSidebar(find.text('By project')));
    await tester.pump();
    for (final label in ['Project', 'Date', 'Status', 'Recent']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Recent'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(workspace.sidebarGrouping, SidebarGrouping.recent.name);
    expect(inSidebar(find.text('By recency')), findsOneWidget);
    final headings = [
      'Pinned',
      'Today',
      'Last 7 days',
      'Last 30 days',
      'Older',
    ];
    for (final label in headings) {
      expect(inSidebar(find.text(label)), findsOneWidget, reason: label);
    }
    final tops = [
      for (final label in headings)
        tester.getTopLeft(inSidebar(find.text(label))).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));

    // Each where it belongs.
    double top(String text) =>
        tester.getTopLeft(inSidebar(find.textContaining(text))).dy;
    expect(top('Rate limit per API key'), greaterThan(top('Today')));
    expect(top('Rate limit per API key'), lessThan(top('Last 7 days')));
    expect(top('Edit sent messages in history'), lessThan(top('Last 30 days')));
    expect(
      top('Translate rules guide to Chinese'),
      greaterThan(top('Last 30 days')),
    );
    expect(top('Flaky integration test on CI'), greaterThan(top('Older')));

    // Date's own groups are as they were.
    await tester.tap(inSidebar(find.text('By recency')));
    await tester.pump();
    await tester.tap(find.text('Date'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(inSidebar(find.text('Previous 7 days')), findsOneWidget);
    expect(inSidebar(find.text('Last 30 days')), findsNothing);
  });

  testWidgets('a grouping it does not know (another build\'s) is by '
      'project', (tester) async {
    final workspace = await pumpApp(tester);
    workspace.sidebarGrouping = 'someday';
    await tester.pump();
    expect(inSidebar(find.text('By project')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one project\'s chats: no other project\'s, no headings of '
      'projects, no Open Project, no By …; a new chat made there', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = Workspace.mock();
    spread(workspace);
    final gateway = named(workspace, 'Rate limit per API key').project;
    final made = <Project?>[];
    AgentThread? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 300,
                child: Sidebar(
                  workspace: workspace,
                  onCollapse: () {},
                  onOpenFolder: () {},
                  project: gateway,
                  grouping: SidebarGrouping.recent,
                  onNewAgent: made.add,
                  onSelect: (thread) => opened = thread,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(inSidebar(find.text('Rate limit per API key')), findsOneWidget);
    expect(
      inSidebar(find.text('Flaky integration test on CI')),
      findsOneWidget,
    );
    expect(
      inSidebar(find.text('Optimize virtual list scrolling')),
      findsNothing,
    );
    expect(inSidebar(find.text('Rewrite the agents quickstart')), findsNothing);
    expect(inSidebar(find.text('api-gateway')), findsNothing);
    expect(inSidebar(find.text('Open Project')), findsNothing);
    expect(inSidebar(find.textContaining('By ')), findsNothing);
    expect(inSidebar(find.text('Today')), findsOneWidget);

    await tester.tap(inSidebar(find.text('New Chat')));
    await tester.pump();
    expect(made, [gateway]);

    await tester.tap(inSidebar(find.text('Rate limit per API key')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opened?.title, 'Rate limit per API key');
  });
}
