// The fork's own strings (docs/fork.md), kept out of lib/l10n/app_*.arb
// and the AppLocalizations generated from them: those are where merging
// upstream conflicts most, so the fork adds nothing to them.
//
// Widgets read them with `context.fork`, in the locale of the
// AppLocalizations in scope: Simplified Chinese for `zh`, else English (as
// `context.l10n` falls back to English where there is none).
import 'package:flutter/widgets.dart';

import '../l10n/l10n.dart';
import '../plan/plan_todos.dart' show PlanTodoState;

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

  // The plan's view (lib/plan/).
  String planTodosCount(int count) =>
      _t(count == 1 ? '1 To-do' : '$count To-dos', '$count 项待办');
  String planTodosSelected(int count) => _t(
    count == 1 ? '1 To-do Selected' : '$count To-dos Selected',
    '已选 $count 项待办',
  );
  String get planUnselect => _t('Clear selection', '取消选择');
  String get planBuildInNewAgent => _t('Build in New Agent', '在新代理中构建');
  String get planBuild => _t('Build', '构建');
  String get planBuildHint =>
      _t('Have the agent do the open to-dos', '让代理完成未完成的待办');
  String get planNew => _t('New', '新建');
  String get planNewPlaceholder =>
      _t('A new to-do, Enter to add', '新待办，按 Enter 添加');
  String get planRun => _t('Run', '运行');
  String get planRunHint => _t('Have the agent do this to-do', '让代理完成这项待办');
  String get planMore => _t('More', '更多');
  String get planDelete => _t('Delete', '删除');
  String get planQueued => _t('Queued', '已排队');
  String get planRunning => _t('In progress', '进行中');
  String get planDone => _t('Done', '已完成');
  String get planCancelled => _t('Cancelled', '已取消');
  String planState(PlanTodoState state) => switch (state) {
    PlanTodoState.pending => _t('Pending', '待办'),
    PlanTodoState.inProgress => _t('In progress', '进行中'),
    PlanTodoState.completed => _t('Completed', '已完成'),
    PlanTodoState.cancelled => _t('Cancelled', '已取消'),
  };
  String get planSaveToProject => _t('Save to Project', '保存到项目');
  String get planPlans => _t('Plans', '计划');
  String get planNoPlans => _t(
    'No plans in this project yet. Plans the agent writes here, and those '
        'saved to .cursor/plans, show here.',
    '此项目还没有计划。代理在此写的计划以及保存到 .cursor/plans 的计划会显示在这里。',
  );
}

extension ForkStringsContext on BuildContext {
  /// The fork's strings in the locale in scope; English when there is none.
  ForkStrings get fork =>
      ForkStrings.forLocale(AppLocalizations.of(this)?.localeName);
}
