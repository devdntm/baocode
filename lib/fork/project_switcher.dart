// Switch Project (docs/fork.md): the IDE's projects in one list. In
// Cursor's layout, the project's name over its chats opens it as a
// dropdown (typed into, it narrows), and ⌃R as a pick. Those open in
// windows of their own first, the window last in front first, then the
// recent ones; each with what its agents need most (the sidebar's mark:
// working, waiting on the user, done unseen). One picked comes in front,
// or opens, as Open Recent's do.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../chat/widgets/hover_builder.dart';
import '../ide/ide_hover.dart';
import '../ide/ide_menu.dart';
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

  /// The dropdown: [current] ticked, then [order]'s projects (open ones,
  /// then the recent), each with its agents' mark and its folder; Open
  /// Folder… at the end ([onOpenFolder]).
  static List<IdeMenuEntry> menu(
    BuildContext context, {
    required String? current,
    required List<({String path, bool open})> projects,
    required ThreadStatus Function(String path) statusOf,
    required ValueChanged<String> onOpen,
    VoidCallback? onOpenFolder,
  }) {
    final l10n = context.l10n;
    IdeMenuAction action(
      String path, {
      bool open = false,
      bool checked = false,
    }) {
      final status = statusOf(path);
      final name = p.basename(path);
      return IdeMenuAction(
        name.isEmpty ? path : name,
        checked: checked,
        icon: SizedBox(
          width: 16,
          child: Center(
            child: status == ThreadStatus.idle
                ? Icon(
                    open ? Codicons.window : Codicons.folder,
                    size: 14,
                    color: AppColors.textFaint,
                  )
                : ThreadStatusMark(status),
          ),
        ),
        // Where it is, on the right, as a menu's keys are.
        keybinding: shortPath(p.dirname(path)),
        onSelected: checked ? null : () => onOpen(path),
      );
    }

    final open = projects.where((project) => project.open).toList();
    final recent = projects.where((project) => !project.open).toList();
    return [
      if (current != null) action(current, open: true, checked: true),
      if (open.isNotEmpty) ...[
        const IdeMenuSeparator(),
        for (final project in open) action(project.path, open: true),
      ],
      if (recent.isNotEmpty) ...[
        const IdeMenuSeparator(),
        for (final project in recent) action(project.path),
      ],
      if (onOpenFolder != null) ...[
        const IdeMenuSeparator(),
        IdeMenuAction(
          l10n.menuOpenFolder,
          // In the icons' column, its label in line with the projects'.
          icon: Icon(
            Codicons.folderOpened,
            size: 14,
            color: AppColors.textFaint,
          ),
          onSelected: onOpenFolder,
        ),
      ],
    ];
  }

  /// [path] as the dropdown shows it, on the right: under the home `~`,
  /// and no longer than [max], its middle folders `…` (then its last one
  /// cut), so a deep one does not widen the menu.
  @visibleForTesting
  static String shortPath(String path, {int max = 32}) {
    final full = _home(path);
    if (full.length <= max) return full;
    final parts = full.split('/');
    final head = parts.first.isEmpty ? '/${parts[1]}' : parts.first;
    final last = parts.last;
    final short = '$head/…/$last';
    if (short.length <= max) return short;
    final room = max - '$head/…/'.length - 1;
    return '$head/…/${last.substring(0, room.clamp(1, last.length))}…';
  }

  static String _home(String path) {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty || !p.isWithin(home, path)) return path;
    return '~/${p.relative(path, from: home)}';
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
        // Its agents' mark in the icon's column, as the sidebar has it: the
        // label's badge would sit right against the name.
        icon: status == ThreadStatus.idle
            ? Icon(project.open ? Codicons.window : Codicons.folder)
            : ThreadStatusMark(status),
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

/// The project's name over its chats in Cursor's layout, with a chevron:
/// [onPressed] with where it is, to open the dropdown under it.
class ProjectSwitchButton extends StatelessWidget {
  const ProjectSwitchButton({
    super.key,
    required this.name,
    required this.tooltip,
    required this.onPressed,
  });

  final String name;
  final String tooltip;
  final ValueChanged<Rect> onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final foreground = colors.get('sideBar.foreground') ?? AppColors.text;
    return Align(
      alignment: Alignment.centerLeft,
      child: IdeHover(
        message: tooltip,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: const ValueKey('fork.switchProject'),
            onTap: () {
              final box = context.findRenderObject()! as RenderBox;
              onPressed(box.localToGlobal(Offset.zero) & box.size);
            },
            child: Container(
              height: 24,
              padding: const EdgeInsets.only(left: 6, right: 4),
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
                        fontSize: 13,
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
      ),
    );
  }
}
