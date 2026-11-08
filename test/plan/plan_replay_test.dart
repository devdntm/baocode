import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/kernel/claude_code/claude_code_translator.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/transcript.dart';
import 'package:flutter_test/flutter_test.dart';

/// A conversation read again after a restart still has its plan: the
/// translator tells of it, marked as read with the history, and the side
/// panel keeps its page without showing it.
void main() {
  const plan = '/Users/me/.claude/plans/quiet-river.md';

  ({Transcript transcript, List<KernelEvent> events}) replay() {
    final transcript = Transcript();
    final events = <KernelEvent>[];
    var seq = 0;
    final translator = ClaudeTranslator(
      emit: (event) {
        events.add(event);
        transcript.apply(event);
      },
      nextSeq: () => ++seq,
    )..replaying = true;
    void use(String id, String name, Map<String, Object?> input) =>
        translator.translate({
          'type': 'assistant',
          'parent_tool_use_id': null,
          'message': {
            'id': 'msg-$id',
            'role': 'assistant',
            'content': [
              {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
            ],
          },
        });
    void result(String id, {String content = 'ok', bool error = false}) =>
        translator.translate({
          'type': 'user',
          'parent_tool_use_id': null,
          'message': {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': id,
                'content': content,
                'is_error': error,
              },
            ],
          },
        });
    use('w1', 'Write', {'file_path': plan, 'content': '# Grow'});
    result('w1');
    use('x1', 'ExitPlanMode', {'plan': '# Grow'});
    result('x1', content: ClaudeTranslator.planPresented, error: true);
    translator.endReplay();
    return (transcript: transcript, events: events);
  }

  test('read with the history: the plan, marked so', () {
    final (:transcript, :events) = replay();
    expect(transcript.plan?.path, plan);
    expect(transcript.planReplayed, isTrue);
    expect(events.whereType<PlanWritten>().single.replayed, isTrue);
    expect(
      [
        for (var i = 0; i < transcript.length; i++)
          if (transcript.itemAt(i) case final PlanItem item) item.path,
      ],
      [plan],
    );
  });

  test('the side panel keeps its page, not shown; one shown stays', () {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final conversation = Object();
    var told = 0;
    panel.addListener(() => told++);
    panel.keepPlan(conversation, plan);
    final tabs = panel.tabsOf(conversation);
    expect(tabs.plan?.path, plan);
    expect(tabs.plan?.request.plan, isTrue);
    expect(tabs.section, isNot(SidePanelSection.plan));
    expect(panel.shown, isFalse);
    expect(told, 1);

    panel.keepPlan(conversation, '/other/plans/x.md');
    expect(tabs.plan?.path, plan);
  });
}
