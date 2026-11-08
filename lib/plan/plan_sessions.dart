// Where a plan's to-dos run (docs/fork.md): the conversation that wrote
// the plan, else the IDE's chat of its folder. The app says which, as it
// starts (workbench.dart); the IDE's plan view asks.

import '../chat/chat_session.dart';

abstract final class PlanSessions {
  /// The conversation whose plan is the file at [path], else [folder]'s
  /// IDE chat; a new one there where [create] and it has none. Null where
  /// there is none, or the app has not said.
  static ChatSession? Function(
    String path, {
    String? folder,
    required bool create,
  })?
  of;

  /// A new conversation to run the plan at [path]'s to-dos in: an agent
  /// in its project, or ([folder]) a new chat of that folder's IDE, shown.
  /// Null where the app has not said how.
  static ChatSession? Function(String path, {String? folder})? created;

  /// What [created] makes; null without it.
  static ChatSession? newSession(String path, {String? folder}) =>
      created?.call(path, folder: folder);

  /// What [of] says; null without it.
  static ChatSession? find(
    String path, {
    String? folder,
    bool create = false,
  }) => of?.call(path, folder: folder, create: create);
}
