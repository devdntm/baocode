// Import from Cursor, the dialog (docs/fork.md): what a project has of
// Cursor's, each part picked to bring over (its rules shown as they would
// be), then brought; its conversations' import goes on with its progress
// here, and on once the dialog is closed.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../extensions/theme_extensions.dart';
import '../../fork/fork_strings.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_dialog.dart' show IdeCheckbox;
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'cursor_import.dart';

/// What the app gives the import: its themes, its keybindings' import.
abstract final class CursorImport {
  static ThemeExtensions? themes;
  static Future<void> Function(BuildContext context)? importKeys;

  /// Shows the dialog for the project at [root].
  static Future<void> open(BuildContext context, String root) async {
    final project = await CursorProject.read(root);
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.l10n.commonDismiss,
      barrierColor: const Color(0x80000000),
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => CursorImportDialog(project: project),
    );
  }
}

class CursorImportDialog extends StatefulWidget {
  const CursorImportDialog({super.key, required this.project});

  final CursorProject project;

  @override
  State<CursorImportDialog> createState() => _CursorImportDialogState();
}

class _CursorImportDialogState extends State<CursorImportDialog> {
  late bool _rules = widget.project.rules.any((rule) => !rule.exists);
  late bool _servers = widget.project.servers.isNotEmpty;
  bool _history = false;
  bool _themes = false;
  final Set<String> _previewed = {};
  bool _importing = false;
  String? _result;
  String? _error;

  CursorHistoryImport? get _historyImport =>
      switch (widget.project.transcripts) {
        final transcripts? => CursorHistoryImport.of(
          widget.project.root,
          transcripts,
        ),
        null => null,
      };

  bool get _historyAvailable =>
      _historyImport != null && CursorHistoryImport.available;

  bool get _themesAvailable =>
      CursorImport.themes != null && Directory(cursorThemesFolder).existsSync();

  bool _importedBefore = false;

  @override
  void initState() {
    super.initState();
    final history = _historyImport;
    if (history != null && _historyAvailable) {
      if (history.total == null && !history.running) {
        unawaited(history.count());
      }
      _importedBefore = _hasCursorJournals();
    }
  }

  bool _hasCursorJournals() {
    final memory = Directory(
      p.join(widget.project.root, '.memsearch', 'memory'),
    );
    if (!memory.existsSync()) return false;
    for (final file in memory.listSync().whereType<File>()) {
      try {
        if (file.readAsStringSync().contains('source:cursor')) return true;
      } on FileSystemException {
        continue;
      }
    }
    return false;
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
    });
    final project = widget.project;
    try {
      final rules = _rules
          ? await project.importRules(project.rules.where((r) => !r.exists))
          : const <String>[];
      if (_servers) await project.importServers(project.servers.keys);
      if (_themes) await importCursorThemes(CursorImport.themes!);
      if (_history) unawaited(_historyImport!.run());
      if (!mounted) return;
      setState(() {
        _result = context.fork.cursorImportDone(
          rules.length,
          _servers ? project.servers.length : 0,
        );
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fork = context.fork;
    final project = widget.project;
    final colors = themeColors;
    final size = MediaQuery.sizeOf(context);
    final history = _historyImport;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
      },
      child: FocusScope(
        autofocus: true,
        child: Align(
          alignment: const Alignment(0, -0.4),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: 560,
              constraints: BoxConstraints(maxHeight: size.height * .85),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              decoration: BoxDecoration(
                color: colors['editorWidget.background'],
                border: switch (colors.get('widget.border')) {
                  final border? => Border.all(color: border),
                  null => null,
                },
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x26000000), blurRadius: 20),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Codicons.cloudDownload,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        fork.cursorImportTitle,
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    project.root,
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (project.rules.isNotEmpty) ...[
                            IdeCheckbox(
                              key: const ValueKey('cursor.import.rules'),
                              label: fork.cursorImportRules(
                                project.rules.where((r) => !r.exists).length,
                              ),
                              checked: _rules,
                              onChanged: () => setState(() => _rules = !_rules),
                            ),
                            for (final rule in project.rules) _ruleRow(rule),
                            const SizedBox(height: 10),
                          ],
                          if (project.servers.isNotEmpty ||
                              project.serversHad.isNotEmpty) ...[
                            if (project.servers.isNotEmpty)
                              IdeCheckbox(
                                key: const ValueKey('cursor.import.servers'),
                                label: fork.cursorImportServers(
                                  project.servers.length,
                                  project.servers.keys.join(', '),
                                ),
                                checked: _servers,
                                onChanged: () =>
                                    setState(() => _servers = !_servers),
                              ),
                            if (project.serversHad.isNotEmpty)
                              _note(
                                fork.cursorImportServersHad(
                                  project.serversHad.join(', '),
                                ),
                              ),
                            const SizedBox(height: 10),
                          ],
                          if (history != null) ...[
                            IdeCheckbox(
                              key: const ValueKey('cursor.import.history'),
                              label: fork.cursorImportHistory(project.sessions),
                              checked: _history,
                              onChanged: () {
                                if (!_historyAvailable || history.running) {
                                  return;
                                }
                                setState(() => _history = !_history);
                              },
                            ),
                            ListenableBuilder(
                              listenable: history,
                              builder: (context, _) => _historyNote(history),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_themesAvailable) ...[
                            IdeCheckbox(
                              key: const ValueKey('cursor.import.themes'),
                              label: fork.cursorImportThemes,
                              checked: _themes,
                              onChanged: () =>
                                  setState(() => _themes = !_themes),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_result case final result?) _note(result),
                          if (_error case final error?)
                            _note(error, color: colors['errorForeground']),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (CursorImport.importKeys case final importKeys?)
                        IdeButton(
                          key: const ValueKey('cursor.import.keys'),
                          label: fork.cursorImportKeys,
                          secondary: true,
                          onPressed: () => unawaited(importKeys(context)),
                        ),
                      const Spacer(),
                      IdeButton(
                        label: fork.cursorImportClose,
                        secondary: true,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      IdeButton(
                        key: const ValueKey('cursor.import.run'),
                        label: fork.cursorImportRun,
                        spinning: _importing,
                        onPressed:
                            _importing ||
                                !(_rules || _servers || _history || _themes)
                            ? null
                            : () => unawaited(_import()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ruleRow(CursorRuleImport rule) {
    final fork = context.fork;
    final name = p.basename(rule.target);
    final open = _previewed.contains(rule.target);
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (!_previewed.remove(rule.target)) _previewed.add(rule.target);
            }),
            child: Row(
              children: [
                Icon(
                  open ? Codicons.chevronDown : Codicons.chevronRight,
                  size: 14,
                  color: AppColors.textFaint,
                ),
                const SizedBox(width: 4),
                Text(
                  name,
                  style: TextStyle(
                    color: rule.exists ? AppColors.textFaint : AppColors.text,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rule.exists
                        ? fork.cursorImportRuleExists
                        : rule.alwaysNow
                        ? fork.cursorImportRuleAlways
                        : '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (open)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.only(top: 4, bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.code,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  rule.text,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                    fontFamily: 'Menlo',
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyNote(CursorHistoryImport history) {
    final fork = context.fork;
    if (!_historyAvailable) return _note(fork.cursorImportHistoryUnavailable);
    if (history.stage != CursorHistoryStage.idle &&
        history.stage != CursorHistoryStage.counting) {
      return _note(
        [
          fork.cursorImportHistoryProgress(
            fork.cursorImportStage(history.stage.name),
            history.done,
            history.total,
          ),
          ?history.error,
        ].join(' · '),
      );
    }
    return _note(
      [
        fork.cursorImportHistoryCost(history.total),
        if (_importedBefore) fork.cursorImportHistoryDone,
      ].join(' '),
    );
  }

  Widget _note(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(left: 24, top: 2),
    child: Text(
      text,
      style: TextStyle(
        color: color ?? AppColors.textFaint,
        fontSize: 12,
        height: 1.4,
      ),
    ),
  );
}
