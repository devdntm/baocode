// The fork's `workbench.ide.layout` setting (docs/fork.md): how the IDE
// lays its parts out. Beside `workbench.mainWindow` (lib/workspace/
// main_window.dart) in what it is, in a file of its own so that upstream's
// stays as it is.

import '../../settings/user_settings.dart';

/// How the IDE lays out its parts: the `workbench.ide.layout` setting.
enum IdeLayoutStyle {
  /// BaoCode's (the default): the views and the side bar on the left, the
  /// editor, the chat on the right ([WorkbenchGrid]).
  standard('default'),

  /// Cursor's: the project's chats and the chat on the left, the editor,
  /// the views over the side bar on the right ([CursorWorkbenchGrid]).
  cursor('cursor');

  const IdeLayoutStyle(this.value);

  /// As settings.json writes it.
  final String value;

  static const settingKey = 'workbench.ide.layout';

  /// When the setting is unset, or not one of these: upstream's layout.
  static const fallback = standard;

  static IdeLayoutStyle parse(Object? setting) =>
      values.where((style) => style.value == setting).firstOrNull ?? fallback;

  /// The one [settings] has; [fallback] where there are none.
  static IdeLayoutStyle of(UserSettings? settings) =>
      parse(settings?[settingKey]);

  /// The other one: what Toggle Cursor Layout switches to.
  IdeLayoutStyle get other => this == cursor ? standard : cursor;

  /// Writes [style] to [settings]; the default is not written.
  static Future<void> select(UserSettings settings, IdeLayoutStyle style) =>
      settings.update(settingKey, style == fallback ? null : style.value);
}
