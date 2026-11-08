import 'package:baocode/chat/side_panel/file_link.dart' show FileLineRange;
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/plan/plan_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// A link to a plan's file in the conversation opens its plan's page; a
/// link to any other file, or to a plan's changes, as before.
void main() {
  test('a plan\'s file, from Claude Code\'s plans or Cursor\'s, on its '
      'page, where it was asked to be', () {
    const range = FileLineRange(3, 5);
    for (final path in [
      '/Users/me/.claude/plans/quiet-river.md',
      '/p/.cursor/plans/roadmap_166f9ad0.plan.md',
    ]) {
      final opened = planPageRequest(FileOpenRequest(path, range: range));
      expect(opened.plan, isTrue, reason: path);
      expect(opened.path, path);
      expect(opened.range, range);
    }
  });

  test('any other file, or a plan\'s changes, as it was', () {
    const notes = FileOpenRequest('/p/docs/notes.md');
    expect(identical(planPageRequest(notes), notes), isTrue);
    const diff = FileOpenRequest('/me/.claude/plans/q.md', diff: true);
    expect(identical(planPageRequest(diff), diff), isTrue);
    const already = FileOpenRequest('/me/.claude/plans/q.md', plan: true);
    expect(identical(planPageRequest(already), already), isTrue);
  });
}
