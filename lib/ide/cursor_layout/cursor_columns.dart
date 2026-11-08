// The width of the project's chats in Cursor's layout (docs/fork.md):
// beside IdeColumns, which sizes the chat, the editor and the side bar in
// the room the chats leave.

import 'dart:math' as math;

import '../ide_columns.dart';
import 'cursor_layout_service.dart';

abstract final class CursorColumns {
  /// The least the parts after the chats need in a row: the editor (unless
  /// [editorHidden]), the chat and the side bar where they are to show,
  /// each at its minimum.
  static double rest({
    required bool sidebar,
    required bool chat,
    required bool editorHidden,
  }) =>
      (editorHidden ? 0 : IdeColumns.minEditor) +
      (chat ? IdeColumns.minChat : 0) +
      (sidebar ? IdeColumns.minSidebar : 0);

  /// The chats' width in a row [width] wide: [agents] (null when hidden;
  /// at least [CursorLayoutService.minAgents]) where what is after them
  /// still has its minimums, else none: in a narrow window they give way
  /// first, before the side bar (IdeColumns.fit), and are back as it
  /// widens.
  static double fit(
    double width, {
    required double? agents,
    required bool sidebar,
    required bool chat,
    required bool editorHidden,
  }) {
    if (agents == null) return 0;
    final wanted = math.max(agents, CursorLayoutService.minAgents);
    final after = rest(
      sidebar: sidebar,
      chat: chat,
      editorHidden: editorHidden,
    );
    return width - wanted >= after ? wanted : 0;
  }

  /// The chats' width with their sash [dx] from where the drag began at
  /// [start]: snapped shut (0) a sixth short of their minimum, as the other
  /// parts snap (IdeColumns.snap); at most what leaves [after] of [width].
  static double drag(
    double start,
    double dx,
    double width, {
    required double after,
  }) {
    const minimum = CursorLayoutService.minAgents;
    final target = start + dx;
    if (target < minimum - IdeColumns.snap(minimum)) return 0;
    final most = width - after;
    if (most < minimum) return start;
    return target.clamp(minimum, most).toDouble();
  }
}
