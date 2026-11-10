// Switch Project (docs/fork.md): the IDE's projects in one list, as the
// project's button in the title bar of Cursor's layout and ⌃R there open
// it. Those open in windows of their own first, the window last in front
// first, then the recent ones; each with what its agents need most (the
// sidebar's mark: working, waiting on the user, done unseen). One picked
// comes in front, or opens, as Open Recent's do.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../chat/widgets/hover_builder.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_quick_input.dart';
import '../l10n/l10n.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/thread_status_mark.dart';
import '../workspace/workspace.dart';
import 'fork_strings.dart';

abstract final class ProjectSwitcher {
  static const commandId = 'fork.switchProject';

  /// The keybindings' context key: true in Cursor's layout, where ⌃R is
  /// Switch Project rather than Open Recent.
  static const layoutKey = 'fork.cursorLayout';

  /// The projects listed: [open] (the window in front first) and then
  /// [recent] not open, none of them [current], each once.
  static List<({String path, bool open})> order({
    required String? current,
    required List<String> open,
    required List<String> recent,
  }) {
    final seen = <String>{if (current != null) p.normalize(current)};
    return [
      for (final path in open)
        if (seen.add(p.normalize(path))) (path: path, open: true),
      for (final path in recent)
        if (seen.add(p.normalize(path))) (path: path, open: false),
    ];
  }

  /// What [path]'s agents need most: the most urgent of their statuses
  /// (the enum is in that order); idle where none needs anything.
  static ThreadStatus statusIn(Workspace workspace, String path) {
    var status = ThreadStatus.idle;
    final key = p.normalize(path);
    for (final thread in workspace.threads) {
      if (thread.archived || p.normalize(thread.project.path) != key) continue;
      final shown = thread.shownStatus;
      if (shown.index < status.index) status = shown;
    }
    return status;
  }

  /// The pick: [order]'s projects, [open] ones under their heading;
  /// [onOpen] opens one picked.
  static IdeQuickPick pick(
    BuildContext context, {
    required List<({String path, bool open})> projects,
    required ThreadStatus Function(String path) statusOf,
    required ValueChanged<String> onOpen,
  }) {
    final l10n = context.l10n;
    final fork = context.fork;
    IdeQuickPickItem item(({String path, bool open}) project) {
      final status = statusOf(project.path);
      final said = switch (status) {
        ThreadStatus.needsInput => l10n.sidebarNeedsInput,
        ThreadStatus.running => l10n.sidebarRunning,
        ThreadStatus.unread => l10n.sidebarUnread,
        ThreadStatus.idle => null,
      };
      final name = p.basename(project.path);
      return IdeQuickPickItem(
        label: name.isEmpty ? project.path : name,
        description: [p.dirname(project.path), ?said].join('  ·  '),
        icon: Icon(project.open ? Codicons.window : Codicons.folder),
        badge: status == ThreadStatus.idle
            ? null
            : SizedBox(
                width: 14,
                child: Center(child: ThreadStatusMark(status)),
              ),
        onAccept: () => onOpen(project.path),
      );
    }

    final open = [
      for (final project in projects.where((p) => p.open)) item(project),
    ];
    final recent = [
      for (final project in projects.where((p) => !p.open)) item(project),
    ];
    return IdeQuickPick(
      items: [
        if (projects.isEmpty)
          IdeQuickPickItem(
            label: l10n.ideNoRecent,
            icon: Icon(Codicons.info, color: AppColors.textFaint),
          ),
        if (open.isNotEmpty) ...[
          IdeQuickPickSeparator(fork.projectSwitcherOpen),
          ...open,
        ],
        if (recent.isNotEmpty) ...[
          IdeQuickPickSeparator(l10n.ideRecentFolders),
          ...recent,
        ],
      ],
      placeholder: fork.projectSwitcherPlaceholder,
      matchOnDescription: true,
      sortByLabel: false,
      onDidAccept: (item) => item?.onAccept?.call(),
    );
  }
}

/// The project's button in the title bar of Cursor's layout: its name and
/// a chevron, opening Switch Project ([onPressed]).
class ProjectSwitchButton extends StatelessWidget {
  const ProjectSwitchButton({
    super.key,
    required this.name,
    required this.tooltip,
    required this.onPressed,
  });

  final String name;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final foreground =
        colors.get('titleBar.activeForeground') ?? AppColors.textMuted;
    return IdeHover(
      message: tooltip,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: const ValueKey('fork.switchProject'),
          onTap: onPressed,
          child: Container(
            height: 22,
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.only(left: 7, right: 4),
            decoration: BoxDecoration(
              color: hovered ? colors['toolbar.hoverBackground'] : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Codicons.chevronDown, size: 14, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
