// Cursor's layout of the parts (docs/fork.md), `workbench.ide.layout`
// `cursor`: the project's chats and the chat on the left, the editor with
// the panel below it, the side bar on the right with the activity bar's
// items in a row over it; the status bar under all. WorkbenchGrid
// (lib/ide/workbench/parts/grid.dart) is BaoCode's; this one takes its
// parts and the widths LayoutService keeps, mirrored. Its editor column is
// grid.dart's (_editorColumn, _panelSlot, _dragPanel), copied: check it
// against that one as upstream is merged.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../debug/ui/debug_toolbar.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart';
import '../../workspace/islands.dart';
import '../ide_columns.dart';
import '../ide_layout.dart';
import '../ide_rows.dart';
import '../ide_status_bar.dart';
import '../ide_tab_bar.dart';
import '../services/debug_view.dart';
import '../services/language.dart';
import '../services/layout.dart';
import '../workbench/options.dart';
import '../workbench/parts/activity_bar.dart';
import '../workbench/parts/editor.dart';
import '../workbench/parts/panel.dart';
import '../workbench/parts/sash.dart';
import '../workbench/parts/side_bar.dart';
import '../workbench/parts/status_bar.dart';
import '../workbench/services.dart';
import '../workbench/style.dart';
import '../workbench/views.dart';
import 'cursor_columns.dart';
import 'cursor_layout_service.dart';

class CursorWorkbenchGrid extends StatefulWidget {
  const CursorWorkbenchGrid({super.key, required this.options, this.agents});

  final WorkbenchOptions options;

  /// The project's chats, left of the chat; none, and there is no column
  /// for them.
  final Widget? agents;

  @override
  State<CursorWorkbenchGrid> createState() => _CursorWorkbenchGridState();
}

class _CursorWorkbenchGridState extends State<CursorWorkbenchGrid> {
  late WorkbenchServices _services;
  late LayoutService _service;
  late CursorLayoutService _cursor;

  /// Which parts show: the workspace's (see [IdeLayout]).
  IdeLayout get _layout => widget.options.workspace.layout;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = WorkbenchScope.of(context);
    _service = _services.get<LayoutService>();
    _cursor = _services.get<CursorLayoutService>();
  }

  /// [change] made to the sizes: the parts laid out again, the window
  /// kept.
  void _resize(VoidCallback change) {
    change();
    _service.resized();
    _cursor.resized();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _service,
      _cursor,
      _services.get<DebugViewService>(),
    ]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) => _split(context, constraints.biggest),
    ),
  );

  /// The widths, and the room for them, when a sash's drag began (see
  /// WorkbenchGrid's).
  ({IdeColumns columns, double room})? _dragStart;

  /// The chats' width, and what the parts after them need, when their
  /// sash's drag began.
  ({double width, double after})? _agentsDragStart;

  /// Whether the chat's sash is being dragged: snapped shut, it stays till
  /// the drag ends, so the drag can bring the chat back.
  bool _chatSashDragging = false;

  /// The panel's height, and the room for it, when its sash's drag began.
  ({IdeRows rows, double room})? _panelDragStart;

  /// The side bar and the chat, which keep their state as they move.
  final _sidebarKey = GlobalKey(debugLabel: 'ide side bar');
  final _chatKey = GlobalKey(debugLabel: 'ide chat');

  /// What [IdeLayout.roomForBoth] and [IdeLayout.roomForSides] are to be,
  /// from the last layout, told after the frame (see WorkbenchGrid's).
  ({bool both, bool sides}) _room = (both: true, sides: true);
  bool _roomPending = false;

  void _noteRoom(({bool both, bool sides}) room) {
    _room = room;
    if ((room.both == _layout.roomForBoth &&
            room.sides == _layout.roomForSides) ||
        _roomPending) {
      return;
    }
    _roomPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _roomPending = false;
      if (mounted) _layout.setRoom(both: _room.both, sides: _room.sides);
    });
  }

  /// Not islands, the line between two parts.
  static BoxDecoration? _line({bool left = false, bool right = false}) =>
      WorkbenchStyle.islands
      ? null
      : BoxDecoration(
          border: Border(
            left: left ? SideBarPart.line : BorderSide.none,
            right: right ? SideBarPart.line : BorderSide.none,
          ),
        );

  /// The chat, which keeps its state as it moves to the editor's place,
  /// maximized, and back: its tabs over its card. Beside the editor it goes
  /// down to the window's foot, its row there in the status bar's: its
  /// branch at the start and how full its context is at the end, as a
  /// chat's window has them. Nothing of the status bar's is in that row,
  /// so no IslandFootTrailing (which would keep the row to its own width,
  /// the meter right after the branch). In the editor's place, no row: the
  /// status bar is under it.
  Widget _chatPart() => Padding(
    key: _chatKey,
    padding: EdgeInsets.symmetric(horizontal: WorkbenchStyle.gap / 2),
    child: HeadedIsland(
      header: IdeTabStrip.height,
      footer: _layout.editorVisible ? Islands.belowHeight : 0,
      color: AppColors.code,
      // Beside the editor, its line on its right.
      border: _layout.editorVisible ? Border(right: SideBarPart.line) : null,
      footerLine: IdeStatusBar.line,
      footerColor: themeColors.get('statusBar.background'),
      child: Focus(focusNode: _service.chatFocus, child: widget.options.chat),
    ),
  );

  /// A part kept mounted (and its state kept) while hidden, [width] wide
  /// (0 hidden), laid out [laidOut] wide.
  Widget _kept(Key key, double width, double laidOut, Widget child) {
    final shown = width > 0;
    return SizedBox(
      key: key,
      width: width,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: laidOut,
        maxWidth: laidOut,
        child: Offstage(
          offstage: !shown,
          child: TickerMode(
            enabled: shown,
            child: ExcludeFocus(excluding: !shown, child: child),
          ),
        ),
      ),
    );
  }

  /// The parts, flush and square, left to right: the project's chats, the
  /// chat, the editor (the panel below it), the side bar under the
  /// activity bar's row; each sash over the line between two. In a narrow
  /// window the chats give way first, then the parts as WorkbenchGrid's
  /// do ([IdeColumns.fit]). With the editor hidden, the chat has its
  /// place, the side bar beside it if that shows; the Git log has the
  /// editor's and the side bar's, under the activity bar's row.
  Widget _split(BuildContext context, Size size) {
    final width = size.width;
    final editorHidden = !_layout.editorVisible;
    final agentsShown = widget.agents != null && _cursor.agents;
    final after = CursorColumns.rest(
      sidebar: _layout.sidebar,
      chat: _layout.chat,
      editorHidden: editorHidden,
    );
    final agents = CursorColumns.fit(
      width,
      agents: agentsShown ? _cursor.agentsWidth : null,
      sidebar: _layout.sidebar,
      chat: _layout.chat,
      editorHidden: editorHidden,
    );
    final room = width - agents;
    _noteRoom((
      both: IdeColumns.roomForBoth(room),
      sides: IdeColumns.roomForSides(room),
    ));
    final columns = IdeColumns.fit(
      room,
      sidebar: _layout.sidebar ? _service.sidebarWidth : null,
      chat: _layout.chat ? _service.chatWidth : null,
      editorHidden: editorHidden,
    );
    final sidebarVisible = columns.sidebar > 0;
    final chatVisible = columns.chat > 0;
    final gitLog =
        !editorHidden &&
        sidebarVisible &&
        _service.view == IdeSideView.sourceControl;
    final height = size.height - IdeStatusBar.height;

    final activityBar = KeyedSubtree(
      key: const ValueKey('ide-activity-bar'),
      child: ActivityBarPart(
        sidebarShowing: sidebarVisible,
        axis: Axis.horizontal,
      ),
    );
    final sideColumn = SizedBox(
      key: const ValueKey('ide-sidebar'),
      width: columns.sidebar,
      child: Container(
        foregroundDecoration: _line(left: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            activityBar,
            Expanded(
              child: KeyedSubtree(
                key: _sidebarKey,
                child: SideBarPart(options: widget.options, border: false),
              ),
            ),
          ],
        ),
      ),
    );

    final agentsSash = WorkbenchSash(
      key: const ValueKey('ide-agents-sash'),
      canMoveBack: agents > 0,
      canMoveForward: width - after > agents + 0.5,
      onStart: () => _agentsDragStart = (width: agents, after: after),
      onDrag: (dx) {
        final start = _agentsDragStart;
        if (start == null) return;
        final next = CursorColumns.drag(
          start.width,
          dx,
          width,
          after: start.after,
        );
        _resize(() {
          if (next > 0) {
            _cursor
              ..agents = true
              ..agentsWidth = next;
          } else if (start.width > 0) {
            // Snapped shut: it opens again as wide as it was.
            _cursor
              ..agents = false
              ..agentsWidth = start.width;
          }
        });
      },
      onReset: () => _resize(() {
        _cursor
          ..agents = true
          ..agentsWidth = CursorLayoutService.defaultAgents;
      }),
    );
    // Mirrored: dragged right, the chat grows; the side bar, left.
    final chatSash = WorkbenchSash(
      key: const ValueKey('ide-chat-sash'),
      canMoveBack: chatVisible,
      canMoveForward: columns.canGrowChat(room),
      onStart: () {
        _dragStart = (columns: columns, room: room);
        _chatSashDragging = true;
      },
      onEnd: () {
        if (mounted) setState(() => _chatSashDragging = false);
      },
      onDrag: (dx) => _dragTo((start, room) => start.dragChat(room, -dx)),
      onReset: () => _resize(() {
        _layout
          ..showChat()
          ..showEditor();
        _service.chatWidth = IdeColumns.defaultChat;
      }),
    );
    final sidebarSash = WorkbenchSash(
      key: const ValueKey('ide-sidebar-sash'),
      canMoveBack: columns.canGrowSidebar(room),
      canMoveForward: sidebarVisible,
      onStart: () => _dragStart = (columns: columns, room: room),
      onDrag: (dx) => _dragTo((start, room) => start.dragSidebar(room, -dx)),
      onReset: () => _resize(() {
        _layout.showSidebar();
        _service.sidebarWidth = IdeColumns.defaultSidebar;
      }),
    );

    final Widget middle;
    if (gitLog) {
      // The Git log in the editor's and the side bar's place, the
      // activity bar's row over it where the side bar was.
      middle = Expanded(
        key: const ValueKey('ide-editor-column'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: columns.sidebar,
                child: Container(
                  foregroundDecoration: _line(left: true),
                  child: activityBar,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _editorColumn(
                  constraints.maxHeight,
                  inPlace: KeyedSubtree(
                    key: _sidebarKey,
                    child: SideBarPart(options: widget.options, border: false),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      middle = Expanded(
        key: const ValueKey('ide-editor-column'),
        child: _editorColumn(
          height,
          inPlace: editorHidden
              ? KeyedSubtree(
                  key: const ValueKey('ide-chat'),
                  child: _chatPart(),
                )
              : null,
        ),
      );
    }

    final language = _services.get<LanguageService>();
    // The status bar's items: [part] of them, `left`, `right` or `all`.
    Widget statusBar({bool left = true, bool right = true}) =>
        ListenableBuilder(
          listenable: language,
          builder: (context, _) => ListenableBuilder(
            listenable: workbenchStatusChanges(_services, widget.options),
            builder: (context, _) {
              final bar = workbenchStatusBar(
                context,
                _services,
                widget.options,
              );
              return IdeStatusBar(
                left: left ? bar.left : const [],
                right: right ? bar.right : const [],
              );
            },
          ),
        );
    // Beside the editor the chat goes down to the window's foot, its own
    // row in the status bar's: the bar's left items under the chats, its
    // right ones under the rest (the left too, the chats hidden).
    final chatToFoot = !editorHidden && chatVisible;
    final statusUnderChats = chatToFoot && agents > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.agents case final list?)
                      _kept(
                        const ValueKey('ide-agents'),
                        agents,
                        agents > 0 ? agents : _cursor.agentsWidth,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Container(
                                color: themeColors['sideBar.background'],
                                foregroundDecoration: _line(right: true),
                                child: list,
                              ),
                            ),
                            if (statusUnderChats) statusBar(right: false),
                          ],
                        ),
                      ),
                    if (!editorHidden)
                      _kept(
                        const ValueKey('ide-chat'),
                        columns.chat,
                        chatVisible ? columns.chat : _service.chatWidth,
                        _chatPart(),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                middle,
                                if (sidebarVisible && !gitLog) sideColumn,
                              ],
                            ),
                          ),
                          if (chatToFoot) statusBar(left: !statusUnderChats),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.agents != null)
                positionedSash(agents, width, agentsSash),
              if (!editorHidden && (chatVisible || _chatSashDragging))
                positionedSash(agents + columns.chat, width, chatSash)
              else if (editorHidden && !sidebarVisible)
                // The chat maximized: its sash is at the right, and
                // dragged back, the editor comes out.
                positionedSash(width, width, chatSash),
              if (!gitLog && !(editorHidden && !sidebarVisible))
                positionedSash(width - columns.sidebar, width, sidebarSash),
            ],
          ),
        ),
        if (!chatToFoot) statusBar(),
      ],
    );
  }

  /// The editor, and below it the panel: grid.dart's `_editorColumn`.
  /// [inPlace] has the editor's place where it is hidden (the chat, or the
  /// Git log), above the panel; the editor is kept.
  Widget _editorColumn(double height, {Widget? inPlace}) {
    final hidden = inPlace != null;
    final shown = _layout.panel != null;
    final room = height;
    final rows = IdeRows.fit(
      room,
      panel: !shown
          ? null
          : _service.panelMaximized
          ? double.infinity
          : _service.panelHeight ?? IdeRows.defaultPanel(room),
      minAbove: hidden ? IdeRows.minChat : IdeRows.minEditor,
    );
    final panelVisible = rows.panel > 0;
    final debug = _services.get<DebugViewService>().service;
    final editor = KeyedSubtree(
      key: const ValueKey('ide-editor'),
      child: EditorPart(options: widget.options),
    );
    final toolbarLocation = debug?.settings().toolBarLocation;
    // In the middle of the gap over the panel's card.
    final sashTop =
        (height -
                rows.panel +
                WorkbenchStyle.gap / 2 -
                WorkbenchStyle.sashWidth / 2)
            .clamp(0.0, math.max(0.0, height - WorkbenchStyle.sashWidth))
            .toDouble();
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Offstage(
                      offstage: hidden,
                      child: TickerMode(
                        enabled: !hidden,
                        child: ExcludeFocus(
                          excluding: hidden,
                          child: toolbarLocation == 'floating' && debug != null
                              ? FloatingDebugToolbar(
                                  service: debug,
                                  child: editor,
                                )
                              : editor,
                        ),
                      ),
                    ),
                    ?inPlace,
                  ],
                ),
              ),
              _panelSlot(rows.panel),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: sashTop,
          height: WorkbenchStyle.sashWidth,
          child: WorkbenchSash(
            key: const ValueKey('ide-panel-sash'),
            axis: Axis.vertical,
            canMoveBack: rows.canGrowPanel(room),
            canMoveForward: panelVisible,
            onStart: () => _panelDragStart = (rows: rows, room: room),
            onDrag: _dragPanel,
            onReset: () => _resize(() {
              _layout.panel ??= _layout.lastPanel;
              _service.panelHeight = null;
            }),
          ),
        ),
      ],
    );
  }

  /// The panel's sash, [dy] from where its drag began: grid.dart's.
  void _dragPanel(double dy) {
    final start = _panelDragStart;
    if (start == null) return;
    final next = start.rows.drag(start.room, dy);
    _resize(() {
      _service.panelMaximized = false;
      if (next.panel > 0) {
        _layout.panel ??= _layout.lastPanel;
        _service.panelHeight = next.panel;
      } else if (start.rows.panel > 0) {
        _layout.panel = null;
        _service.panelHeight = start.rows.panel;
      }
    });
  }

  /// The panel, kept mounted (and its terminals running) while hidden.
  Widget _panelSlot(double height) {
    final shown = height > 0;
    final laidOut = shown ? height : _service.panelHeight ?? IdeRows.minPanel;
    return SizedBox(
      key: const ValueKey('ide-panel'),
      height: height,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: laidOut,
        maxHeight: laidOut,
        child: Offstage(
          offstage: !shown,
          child: TickerMode(
            enabled: shown,
            child: ExcludeFocus(
              excluding: !shown,
              child: PanelPart(options: widget.options),
            ),
          ),
        ),
      ),
    );
  }

  /// Where a sash's drag has got to, [drag] from its start: grid.dart's
  /// `_dragTo`, the widths being the same, only mirrored on the screen.
  void _dragTo(IdeColumns Function(IdeColumns start, double room) drag) {
    final start = _dragStart;
    if (start == null) return;
    final columns = start.columns;
    final next = drag(columns, start.room);
    _resize(() {
      if (next.sidebar > 0) {
        _service.sidebarWidth = next.sidebar;
      } else if (columns.sidebar > 0) {
        _service.sidebarWidth = columns.sidebar;
      }
      if (next.editorHidden) {
        if (!columns.editorHidden && columns.chat > 0) {
          _service.chatWidth = columns.chat;
        }
      } else if (next.chat > 0) {
        if (!columns.editorHidden || columns.sidebar == 0) {
          _service.chatWidth = next.chat;
        }
      } else if (columns.chat > 0 && !columns.editorHidden) {
        _service.chatWidth = columns.chat;
      }
      _layout.resize(
        sidebar:
            !next.chatMaximized &&
            (next.sidebar > 0 || (columns.sidebar == 0 && _layout.sidebar)),
        chat: next.chat > 0 || (columns.chat == 0 && _layout.chat),
        editorHidden: next.editorHidden,
      );
    });
  }
}
