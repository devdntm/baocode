// What Cursor's layout has beyond LayoutService's (docs/fork.md): the
// project's chats, left of the chat. Kept with the window's view state, as
// LayoutService's widths are, under keys of its own: a window kept by
// upstream's build reads as before, and upstream's reads one kept here.

import 'package:flutter/foundation.dart';

import '../workbench/storage.dart';

class CursorLayoutService extends ChangeNotifier
    implements WorkbenchStorageParticipant {
  /// Whether the project's chats show, as the user left them; where the
  /// window is too narrow they give way first (see [CursorColumns.fit]).
  bool get agents => _agents;
  bool _agents = true;
  set agents(bool value) {
    if (value == _agents) return;
    _agents = value;
    notifyListeners();
  }

  void toggleAgents() => agents = !agents;

  /// The width they open at, and have while there is room. Set as their
  /// sash is dragged.
  double agentsWidth = defaultAgents;

  static const minAgents = 200.0;
  static const defaultAgents = 260.0;

  /// A sash dragged or reset.
  void resized() => notifyListeners();

  @override
  void restoreState(Map<String, Object?> kept) {
    if (kept[agentsWidthKey] case final num width
        when width.isFinite && width > 0) {
      agentsWidth = width.toDouble();
    }
    _agents = kept[agentsKey] != false;
    notifyListeners();
  }

  /// Only what is not the default: a window kept as upstream keeps it
  /// where they were never changed.
  @override
  void saveState(Map<String, Object?> into) {
    if (agentsWidth != defaultAgents) into[agentsWidthKey] = agentsWidth;
    if (!_agents) into[agentsKey] = false;
  }

  static const agentsWidthKey = 'cursor.agentsWidth';
  static const agentsKey = 'cursor.agents';
}
