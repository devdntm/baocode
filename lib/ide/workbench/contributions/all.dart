// The features' contributions, made as a window is: the order is the
// order their actions are tried in (of two with an id, the first runs).

// fork: the fork's contributions (docs/fork.md).
import '../../cursor_layout/layout_contribution.dart';
import '../../../plan/plan_contribution.dart';
import '../../../integrations/claude_context/claude_context_ui.dart';
import '../../../integrations/cursor_import/cursor_import_ui.dart';
import '../contributions.dart';
import '../services.dart';
import 'debug.dart';
import 'editor_panes.dart';
import 'editor_commands.dart';
import 'editor_status.dart';
import 'explorer.dart';
import 'extensions.dart';
import 'focus_keys.dart';
import 'language.dart';
import 'layout.dart';
import 'lists.dart';
import 'markdown.dart';
import 'navigation.dart';
import 'quick_input.dart';
import 'scm.dart';
import 'search.dart';
import 'terminal.dart';
import 'window.dart';

List<WorkbenchContribution> createWorkbenchContributions(
  WorkbenchServices services,
) => [
  NavigationContribution(services),
  ScmContribution(services),
  TerminalContribution(services),
  EditorPanesContribution(services),
  EditorStatusContribution(services),
  MarkdownContribution(services),
  DebugContribution(services),
  LanguageContribution(services),
  ListsContribution(services),
  ExplorerContribution(services),
  LayoutContribution(services),
  QuickInputContribution(services),
  SearchContribution(services),
  EditorCommandsContribution(services),
  WindowContribution(services),
  ExtensionsContribution(services),
  // fork: Toggle Cursor Layout; a plan's file as Cursor shows it.
  CursorLayoutContribution(services),
  PlanContribution(services),
  // fork: the claude-context index in the status bar; Import from Cursor.
  ClaudeContextContribution(services),
  CursorImportContribution(services),
  // Last: the text editor's own keys are asked after every other's.
  FocusKeysContribution(services),
];
