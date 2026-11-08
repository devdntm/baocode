import 'package:baocode/ide/markdown/markdown_preview.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/plan/plan_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ide/workbench/fake_files.dart';

const _plan = '''
---
name: A plan
overview: What it is for.
todos:
  - id: a
    content: Do it
    status: pending
isProject: false
---

# A plan

Some text.
''';

/// A plan's file in the IDE's editor: its preview, its to-dos under its
/// text in the same scroll, its front matter its overview alone; any
/// other markdown file's preview as it was.
void main() {
  setUp(() {
    KeybindingService.instance = KeybindingService();
    PlanFiles.read = (path) async => path.endsWith('p.md') ? _plan : null;
    PlanFiles.modified = null;
  });
  tearDown(() => KeybindingService.instance = KeybindingService());

  testWidgets('a plan: its to-dos under its text, in its preview', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'plans/p.md': _plan}, open: ['plans/p.md']);
    await tester.pump();
    await tester.pump();
    final preview = find.byType(IdeMarkdownPreview);
    expect(preview, findsOneWidget);
    final block = find.descendant(
      of: preview,
      matching: find.byType(PlanTodosBlock),
    );
    expect(block, findsOneWidget);
    expect(find.text('Do it'), findsOneWidget);
    expect(
      tester.getTopLeft(block).dy,
      greaterThan(
        tester
            .getTopLeft(find.textContaining('Some text.', findRichText: true))
            .dy,
      ),
    );
    // Its overview, not its keys.
    expect(find.text('What it is for.'), findsOneWidget);
    expect(find.textContaining('isProject', findRichText: true), findsNothing);
    expect(
      find.ancestor(of: preview, matching: find.byType(PlanContext)),
      findsOneWidget,
    );
  });

  testWidgets('another markdown file, its preview alone', (tester) async {
    await pumpWorkbench(
      tester,
      {'docs/p.md': '# Notes\n'},
      open: ['docs/p.md'],
    );
    await tester.pump();
    expect(find.byType(IdeMarkdownPreview), findsOneWidget);
    expect(find.byType(PlanTodosBlock), findsNothing);
  });
}
