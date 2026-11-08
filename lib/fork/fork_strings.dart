// The fork's own strings (docs/fork.md), kept out of lib/l10n/app_*.arb
// and the AppLocalizations generated from them: those are where merging
// upstream conflicts most, so the fork adds nothing to them.
//
// Widgets read them with `context.fork`, in the locale of the
// AppLocalizations in scope: Simplified Chinese for `zh`, else English (as
// `context.l10n` falls back to English where there is none).
import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';

/// The fork's strings in one language: each getter gives the English or
/// the Chinese, as AppLocale's two languages.
class ForkStrings {
  const ForkStrings({this.chinese = false});

  /// The strings for [localeName] (AppLocalizations' `localeName`, as `en`
  /// or `zh_CN`).
  factory ForkStrings.forLocale(String? localeName) =>
      ForkStrings(chinese: localeName?.split(RegExp('[-_]')).first == 'zh');

  final bool chinese;

  String _t(String en, String zh) => chinese ? zh : en;

  // workbench.ide.layout (lib/ide/cursor_layout/).
  String get ideLayoutTitle => _t('IDE layout', 'IDE 布局');
  String get ideLayoutDescription => _t(
    'Where the chat, the editor and the views sit in IDE mode.',
    'IDE 模式下聊天、编辑器和视图的位置。',
  );
  String get ideLayoutDefault => _t('BaoCode', 'BaoCode');
  String get ideLayoutCursor => _t('Cursor', 'Cursor');

  // The project's chats in Cursor's layout (lib/ide/cursor_layout/).
  String get ideToggleAgents => _t('Toggle Chats', '切换聊天列表');

  // SidebarGrouping.recent (lib/sidebar/sidebar.dart).
  String get sidebarGroupingRecent => _t('Recent', '最近');
  String get sidebarByRecent => _t('By recency', '按时间段');
  String get sidebarLast7Days => _t('Last 7 days', '最近 7 天');
  String get sidebarLast30Days => _t('Last 30 days', '最近 30 天');
}

extension ForkStringsContext on BuildContext {
  /// The fork's strings in the locale in scope; English when there is none.
  ForkStrings get fork =>
      ForkStrings.forLocale(AppLocalizations.of(this)?.localeName);
}
