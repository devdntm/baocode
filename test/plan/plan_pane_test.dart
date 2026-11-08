import 'package:baocode/ide/markdown/markdown_preview.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/plan/plan_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ide/workbench/fake_files.dart';

/// A plan's file in the IDE's editor: its preview under its to-dos; any
/// other markdown file's preview alone.
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  testWidgets('a plan in a plans folder shows in the plan\'s view, its '
      'preview in it', (tester) async {
    await pumpWorkbench(
      tester,
      {'plans/p.md': '# A plan\n\n## Tasks\n\n- [ ] [a] Do it\n'},
      open: ['plans/p.md'],
    );
    await tester.pump();
    expect(find.byType(PlanView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(PlanView),
        matching: find.byType(IdeMarkdownPreview),
      ),
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
    expect(find.byType(PlanView), findsNothing);
    expect(find.byType(IdeMarkdownPreview), findsOneWidget);
  });
}
