// A plan's file in the IDE's editor, as Cursor shows it (docs/fork.md):
// its markdown preview, its to-dos under its text (PlanPreview), run in
// the folder's IDE chat (PlanContext). Its source is the text editor's,
// as any markdown file's.

import 'package:flutter/widgets.dart';

import '../ide/ide_workspace.dart';
import '../ide/markdown/markdown_preview.dart' show IdeMarkdownPreviewState;
import '../ide/services/markdown_preview.dart';
import '../ide/workbench/contributions.dart';
import '../ide/workbench/editor_panes.dart';
import '../ide/workbench/services.dart';
import 'plan_view.dart';

class PlanContribution extends WorkbenchRegistrations {
  PlanContribution(WorkbenchServices services) {
    final markdown = services.get<MarkdownPreviewService>();
    add(
      services.get<EditorPaneRegistry>().register(
        EditorPane(
          id: paneId,
          accepts: (doc) =>
              PlanPreview.isPlan(doc.path) && markdown.previewing(doc),
          build: (context, doc) => PlanContext(
            folder: services.find<IdeWorkspace>()?.root,
            child: markdown.build(doc),
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
