// The project's chats in Cursor's layout (docs/fork.md): the agents'
// Sidebar, of the IDE's folder only, grouped by when each was last at
// (SidebarGrouping.recent); a chat picked or made opens in the IDE's chat.
// And its toggle, for the title bar.

import 'package:flutter/widgets.dart';

import '../../fork/fork_strings.dart';
import '../../sidebar/sidebar.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart';
import '../../update/update_service.dart';
import '../../workspace/workspace.dart';
import '../ide_hover.dart';
import '../workbench/services.dart';
import 'cursor_layout_service.dart';

class IdeAgentsBar extends StatelessWidget {
  const IdeAgentsBar({
    super.key,
    required this.workspace,
    required this.folder,
    required this.project,
    required this.onOpen,
    required this.onNew,
    this.onSearch,
    this.onCustomize,
    this.onStash,
    this.stashes,
    this.onOpenSettings,
    this.updates,
    this.onUpdate,
    this.setup,
    this.projectSwitcher,
  });

  final Workspace workspace;

  /// The IDE's folder, whose chat [Workspace.ideChat] is the one selected.
  final String folder;

  /// Its project: only its agents are listed.
  final Project project;

  /// Opens an agent in the IDE's chat, as a tab of it.
  final ValueChanged<AgentThread> onOpen;

  /// A new chat in the folder, in the IDE's chat.
  final VoidCallback onNew;

  /// As the chat's sidebar has them (see [Sidebar]).
  final VoidCallback? onSearch;
  final VoidCallback? onCustomize;
  final VoidCallback? onStash;
  final SidebarStashes? stashes;
  final VoidCallback? onOpenSettings;
  final UpdateService? updates;
  final VoidCallback? onUpdate;
  final Widget? setup;

  /// Over the chats: the project's name, its dropdown of the others
  /// (lib/fork/project_switcher.dart).
  final Widget? projectSwitcher;

  @override
  Widget build(BuildContext context) {
    final cursor = WorkbenchScope.maybeOf(context)?.find<CursorLayoutService>();
    // The chat selected follows the IDE's tabs.
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) => Sidebar(
        workspace: workspace,
        project: project,
        grouping: SidebarGrouping.recent,
        topLeading: projectSwitcher,
        surface: themeColors['sideBar.background'],
        current: workspace.ideChat(folder),
        onSelect: onOpen,
        onNewAgent: (_) => onNew(),
        onCollapse: () => cursor?.agents = false,
        onSearch: onSearch,
        onCustomize: onCustomize,
        onStash: onStash,
        stashes: stashes,
        onOpenSettings: onOpenSettings,
        updates: updates,
        onUpdate: onUpdate,
        setup: setup,
      ),
    );
  }
}

/// The title bar's toggle of the project's chats, where Cursor's layout
/// shows them; nothing where there is no [CursorLayoutService].
class CursorAgentsToggle extends StatelessWidget {
  const CursorAgentsToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final cursor = WorkbenchScope.maybeOf(context)?.find<CursorLayoutService>();
    if (cursor == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: cursor,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: IdeActionButton(
          key: const ValueKey('cursor.agents.toggle'),
          icon: Codicons.commentDiscussion,
          tooltip: context.fork.ideToggleAgents,
          checked: cursor.agents,
          onPressed: cursor.toggleAgents,
        ),
      ),
    );
  }
}
