// Import from Cursor, the dialog (docs/fork.md): what a project has of
// Cursor's, each part picked to bring over (its rules shown as they would
// be, its skills as they are), then brought; its conversations' import goes on with its progress
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

  static final Set<String> _open = {};

  /// Whether the dialog for [root] shows: its import's end is told there.
  static bool isOpen(String root) => _open.contains(root);

  /// Shows the dialog for the project at [root].
  static Future<void> open(BuildContext context, String root) async {
    if (isOpen(root)) return;
    _open.add(root);
    try {
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
    } finally {
      _open.remove(root);
    }
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
  late bool _skills = widget.project.skills.any((skill) => !skill.exists);
  late bool _servers = widget.project.servers.isNotEmpty;
  bool _history = false;
  bool _themes = false;
  final Set<String> _previewed = {};

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

  CursorImportJob get _job => CursorImportJob.of(widget.project.root);

  /// Whether it shows the import's progress, not its parts to pick: once
  /// started here, or opened again while it goes on or before its end
  /// was seen.
  late bool _progress = _job.parts.isNotEmpty && (_job.running || _job.unseen);

  void _import() {
    setState(() => _progress = true);
    unawaited(
      _job.start(
        widget.project,
        rules: _rules,
        skills: _skills,
        servers: _servers,
        themes: _themes ? CursorImport.themes : null,
        history: _history ? _historyImport : null,
      ),
    );
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
                          if (_progress)
                            ListenableBuilder(
                              listenable: _job,
                              builder: (context, _) => _progressView(),
                            )
                          else ...[
                            if (project.rules.isNotEmpty) ...[
                              IdeCheckbox(
                                key: const ValueKey('cursor.import.rules'),
                                label: fork.cursorImportRules(
                                  project.rules.where((r) => !r.exists).length,
                                ),
                                checked: _rules,
                                onChanged: () =>
                                    setState(() => _rules = !_rules),
                              ),
                              for (final rule in project.rules)
                                _fileRow(
                                  path: rule.target,
                                  name: p.basename(rule.target),
                                  exists: rule.exists,
                                  note: rule.alwaysNow
                                      ? fork.cursorImportRuleAlways
                                      : '',
                                  text: rule.text,
                                ),
                              const SizedBox(height: 10),
                            ],
                            if (project.skills.isNotEmpty) ...[
                              IdeCheckbox(
                                key: const ValueKey('cursor.import.skills'),
                                label: fork.cursorImportSkills(
                                  project.skills.where((s) => !s.exists).length,
                                ),
                                checked: _skills,
                                onChanged: () =>
                                    setState(() => _skills = !_skills),
                              ),
                              for (final skill in project.skills)
                                _fileRow(
                                  path: skill.target,
                                  name: skill.name,
                                  exists: skill.exists,
                                  note: skill.description,
                                  text: skill.text,
                                ),
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
                                label: fork.cursorImportHistory(
                                  project.sessions,
                                ),
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
                          ],
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
                        key: const ValueKey('cursor.import.close'),
                        label: fork.cursorImportClose,
                        secondary: !_progress,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      if (!_progress)
                        IdeButton(
                          key: const ValueKey('cursor.import.run'),
                          label: fork.cursorImportRun,
                          onPressed:
                              !(_rules ||
                                  _skills ||
                                  _servers ||
                                  _history ||
                                  _themes)
                              ? null
                              : _import,
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

  /// A rule or a skill: its name, a note, its text shown when tapped.
  Widget _fileRow({
    required String path,
    required String name,
    required bool exists,
    required String note,
    required String text,
  }) {
    final fork = context.fork;
    final open = _previewed.contains(path);
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (!_previewed.remove(path)) _previewed.add(path);
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
                    color: exists ? AppColors.textFaint : AppColors.text,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exists ? fork.cursorImportRuleExists : note,
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
                  text,
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

  /// Each part asked for, how far it is, and that the window can be
  /// closed while it goes on.
  Widget _progressView() {
    final fork = context.fork;
    final project = widget.project;
    final job = _job;
    // Its end shown here: the status bar has nothing more to tell.
    if (!job.running && job.unseen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => job.seen());
    }
    String label(String part) {
      final count = job.counts[part];
      return switch (part) {
        'rules' => fork.cursorImportRules(
          count ?? project.rules.where((r) => !r.exists).length,
        ),
        'skills' => fork.cursorImportSkills(
          count ?? project.skills.where((s) => !s.exists).length,
        ),
        'servers' => fork.cursorImportServers(
          count ?? project.servers.length,
          project.servers.keys.join(', '),
        ),
        'themes' => fork.cursorImportThemes,
        _ => fork.cursorImportHistory(project.sessions),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: part, value: stage) in job.parts.entries) ...[
          _partRow(label(part), stage),
          if (job.errors[part] case final error? when error.isNotEmpty)
            _note(error, color: themeColors['errorForeground']),
          if (part == 'history' && job.history != null)
            _historyProgress(job.history!),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Text(
          job.running
              ? fork.cursorImportCloseHint
              : job.failed
              ? fork.cursorImportFailed
              : fork.cursorImportFinished,
          key: const ValueKey('cursor.import.status'),
          style: TextStyle(
            color: job.running || !job.failed
                ? AppColors.textMuted
                : themeColors['errorForeground'],
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _partRow(String label, CursorPartStage stage) => Row(
    children: [
      SizedBox.square(
        dimension: 16,
        child: switch (stage) {
          CursorPartStage.running => Padding(
            padding: const EdgeInsets.all(2),
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: AppColors.textMuted,
            ),
          ),
          CursorPartStage.done => Icon(
            Codicons.check,
            size: 16,
            color: themeColors.get('testing.iconPassed') ?? AppColors.textMuted,
          ),
          CursorPartStage.failed => Icon(
            Codicons.error,
            size: 16,
            color: themeColors['errorForeground'],
          ),
        },
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: TextStyle(color: AppColors.text, fontSize: 12.5),
        ),
      ),
    ],
  );

  /// The conversations' stage and a bar of the turns told so far.
  Widget _historyProgress(CursorHistoryImport history) {
    final fork = context.fork;
    final stage = fork.cursorImportStage(history.stage.name);
    final summarizing = history.stage == CursorHistoryStage.summarizing;
    final total = history.total;
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            summarizing
                ? fork.cursorImportHistoryProgress(stage, history.done, total)
                : stage,
            style: TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
          if (history.running) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: summarizing && total != null && total > 0
                    ? history.done / total
                    : null,
                color: themeColors['progressBar.background'],
                backgroundColor: AppColors.code,
              ),
            ),
          ],
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
