// A plan's file in the IDE's editor, as Cursor shows it (docs/fork.md):
// its preview under its to-dos (PlanView), in place of the markdown
// preview alone. Its source is the text editor's, as any markdown file's.

import 'package:flutter/widgets.dart';

import '../ide/ide_workspace.dart';
import '../ide/markdown/markdown_preview.dart' show IdeMarkdownPreviewState;
import '../ide/services/markdown_preview.dart';
import '../ide/workbench/contributions.dart';
import '../ide/workbench/editor_panes.dart';
import '../ide/workbench/services.dart';
import '../kernel/claude_code/claude_code_translator.dart';
import 'plan_view.dart';

class PlanContribution extends WorkbenchRegistrations {
  PlanContribution(WorkbenchServices services) {
    final markdown = services.get<MarkdownPreviewService>();
    add(
      services.get<EditorPaneRegistry>().register(
        EditorPane(
          id: paneId,
          accepts: (doc) =>
              ClaudeTranslator.isPlanPath(doc.path) && markdown.previewing(doc),
          build: (context, doc) => PlanView(
            key: ValueKey(('plan', doc.path)),
            path: doc.path,
            folder: services.find<IdeWorkspace>()?.root,
            showBuild: true,
            body: markdown.build(doc),
          ),
          control: (doc) => switch (markdown.previewOf(doc)) {
            final preview? => _PreviewControl(preview),
            null => null,
          },
        ),
        // Over the markdown preview, which it has under it.
        priority: EditorPanePriority.markdownPreview + 50,
      ),
    );
  }

  static const paneId = 'fork.editor.plan';
}

/// The preview's, as the markdown pane's (contributions/markdown.dart).
class _PreviewControl implements EditorPaneControl {
  _PreviewControl(this.preview);

  final IdeMarkdownPreviewState preview;

  @override
  void focus() => preview.focus();

  @override
  void revealLine(int line, [int column = 1]) =>
      preview.revealLine(line, column);
}
