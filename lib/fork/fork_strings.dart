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

  // The browser's page (lib/fork/browser/), as upstream had it before
  // 1.9.0 took it out.
  String get browserPage => _t('Browser', '浏览器');
  String get browserNotConnected => _t(
    "No browser is connected. Add BaoCode's extension to Chrome (or Edge, "
        'Brave, Arc) and agents can use the tabs you share with them.',
    '没有连接浏览器。在 Chrome（或 Edge、Brave、Arc）中添加 BaoCode 扩展后，agent 就能使用你共享给它的标签页。',
  );
  String get browserNoSharedTab => _t(
    'No tab is shared yet. Ask an agent to open a page, or click BaoCode '
        'in the browser toolbar to share the tab in front.',
    '还没有共享的标签页。让 agent 打开网页，或在浏览器工具栏点 BaoCode 按钮共享当前标签页。',
  );
  String get browserSharedTabs => _t('Shared Tabs', '共享的标签页');
  String get browserReload => _t('Reload', '重新加载');
  String get browserShowInBrowser => _t('Show in Browser', '在浏览器中显示');
  String get browserDetached => _t(
    'The browser stopped letting BaoCode see this tab.',
    '浏览器已停止让 BaoCode 查看这个标签页。',
  );
  String get browserReconnect => _t('Reconnect', '重新连接');
  String get browserShowInPage => _t('Show in Browser Tab', '在浏览器标签页中查看');
  String get browserOpenCommand => _t('Open Browser', '打开浏览器');
  String get planNoneOpen => _t(
    'Pick a plan at the left, or open one from the conversation.',
    '在左侧选择一个计划，或从对话中打开。',
  );
  String get planSavedToProject => _t('Saved to Project', '已保存到项目');
  String get planNoPlans => _t(
    'No plans in this project yet. Plans the agent writes here, and those '
        'saved to .cursor/plans, show here.',
    '此项目还没有计划。代理在此写的计划以及保存到 .cursor/plans 的计划会显示在这里。',
  );

  // The claude-context index (lib/integrations/claude_context/).
  String get indexChecking => _t('Index…', '索引…');
  String indexFiles(int indexed, int total) =>
      _t('Index $indexed/$total', '索引 $indexed/$total');
  String indexRunning(String share) => _t('Indexing $share', '正在索引 $share');
  String get indexNotIndexed => _t('Not indexed', '未索引');
  String get indexInterrupted => _t('Index interrupted', '索引已中断');
  String get indexFailed => _t('Index error', '索引出错');
  String get indexTooltip => _t(
    'claude-context: what of the project is indexed for semantic search',
    'claude-context：项目中已为语义搜索建立索引的部分',
  );
  String indexSummary(int indexed, int? total, int chunks) => _t(
    '$indexed of ${total ?? '?'} files indexed, $chunks chunks',
    '已索引 $indexed / ${total ?? '?'} 个文件，$chunks 个片段',
  );
  String indexMissingIn(String dir, int count) =>
      _t('$count missing in $dir', '$dir 中缺少 $count 个');
  String get indexRun => _t('Index', '建立索引');
  String get indexForce => _t('Reindex All…', '全部重建索引…');
  String get indexCheck => _t('Check', '检查');
  String get indexForceTitle =>
      _t('Index the whole project again?', '重新为整个项目建立索引？');
  String get indexForceDetail => _t(
    'Its index is dropped and made again from every file: a large project '
        'takes minutes (about 12 chunks a second).',
    '将删除现有索引并从所有文件重新建立：大型项目需要数分钟（约每秒 12 个片段）。',
  );
  String get indexProject => _t('Index for Search', '为搜索建立索引');
  String get indexInterruptedHint => _t(
    'The server indexing it stopped before it was done: index it again, all '
        'of it.',
    '建立索引的服务器在完成前已停止：请重新为整个项目建立索引。',
  );

  // Import from Cursor (lib/integrations/cursor_import/).
  String get cursorImportTitle => _t('Import from Cursor', '从 Cursor 导入');
  String get cursorImportAction => _t('Import from Cursor…', '从 Cursor 导入…');
  String get cursorImportBanner => _t(
    'This project was used in Cursor: bring its rules, skills, MCP servers '
        'and conversations over?',
    '此项目曾在 Cursor 中使用：要导入它的规则、技能、MCP 服务器和对话吗？',
  );
  String get cursorImportDismiss => _t('Not now', '暂不');
  String cursorImportRules(int count) =>
      _t('Rules: $count → .claude/rules', '规则：$count 条 → .claude/rules');
  String cursorImportSkills(int count) =>
      _t('Skills: $count → .claude/skills', '技能：$count 个 → .claude/skills');
  String get cursorImportRuleExists => _t('exists, kept', '已存在，保留');
  String get cursorImportRuleAlways => _t(
    'Cursor applied it when relevant; Claude Code reads it always',
    'Cursor 仅在相关时应用；Claude Code 始终读取',
  );
  String cursorImportServers(int count, String names) => _t(
    'MCP servers: $count → .mcp.json ($names)',
    'MCP 服务器：$count 个 → .mcp.json（$names）',
  );
  String cursorImportServersHad(String names) =>
      _t('Already in .mcp.json: $names', '.mcp.json 中已有：$names');
  String cursorImportHistory(int sessions) => _t(
    'Conversations: $sessions → memsearch memory',
    '对话：$sessions 个 → memsearch 记忆',
  );
  String cursorImportHistoryCost(int? turns) => _t(
    turns == null
        ? 'Counting the turns to summarize…'
        : '$turns turns to summarize, each a call of Claude Haiku: paid, '
              'and minutes long.',
    turns == null
        ? '正在统计需要总结的轮次…'
        : '需要总结 $turns 轮，每轮调用一次 Claude Haiku：需付费，耗时数分钟。',
  );
  String get cursorImportHistoryDone => _t(
    'Imported before: days that have Cursor\'s turns already are kept.',
    '之前已导入：已含 Cursor 记录的日期会保留。',
  );
  String get cursorImportHistoryUnavailable =>
      _t('Needs the memsearch plugin and its CLI.', '需要 memsearch 插件及其命令行工具。');
  String cursorImportHistoryProgress(String stage, int done, int? total) =>
      _t('$stage: $done/${total ?? '?'}', '$stage：$done/${total ?? '?'}');
  String cursorImportStage(String stage) => switch (stage) {
    'summarizing' => _t('Summarizing', '正在总结'),
    'assembling' => _t('Writing the journals', '正在写入日志'),
    'indexing' => _t('Indexing the memory', '正在索引记忆'),
    'done' => _t('Done', '完成'),
    'failed' => _t('Failed', '失败'),
    _ => _t('Counting', '正在统计'),
  };
  String get cursorImportThemes => _t(
    'Cursor\'s themes (Cursor Dark Midnight…)',
    'Cursor 主题（Cursor Dark Midnight…）',
  );
  String get cursorImportKeys => _t('Keybindings…', '快捷键…');
  String get cursorImportRun => _t('Import', '导入');
  String get cursorImportClose => _t('Close', '关闭');
  String cursorImportDone(int rules, int skills, int servers) => _t(
    'Imported: $rules rules, $skills skills, $servers MCP servers.',
    '已导入：$rules 条规则，$skills 个技能，$servers 个 MCP 服务器。',
  );
}

extension ForkStringsContext on BuildContext {
  /// The fork's strings in the locale in scope; English when there is none.
  ForkStrings get fork =>
      ForkStrings.forLocale(AppLocalizations.of(this)?.localeName);
}
