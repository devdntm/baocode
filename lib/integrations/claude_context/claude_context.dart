// A project's claude-context index (docs/fork.md): how much of it is
// indexed, read in Milvus by BaoCode's helper (tool/claude_context/
// bao_index.js), never by get_indexing_status, which lies while indexing;
// and an indexing run, which the helper holds for BaoCode (not Claude
// Code's server, which goes with its session). The IDE's status bar and the
// sidebar's project menu show it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../../customize/customization_store.dart';
import '../../customize/customizations.dart';
import '../../platform/child_process_registry.dart';
import '../../platform/data_dir.dart';
import '../../remote/remote_location.dart';

/// Where a project's index is.
enum ClaudeContextState {
  /// Not looked at yet.
  unknown,

  /// Being looked at.
  checking,

  /// Not indexed at all.
  notIndexed,

  /// Every file of the project is in it.
  complete,

  /// Some of its files are not.
  incomplete,

  /// Being indexed (by BaoCode's run, or Claude Code's server).
  indexing,

  /// Left "indexing" by a server that is gone: cut short, to index again.
  interrupted,

  /// The last run or look failed.
  failed,
}

/// What the helper found: [ClaudeContextReport.fromJson] of its JSON.
@immutable
class ClaudeContextReport {
  const ClaudeContextReport({
    required this.exists,
    this.chunks = 0,
    this.indexedFiles = 0,
    this.projectFiles,
    this.missing,
    this.missingByDir = const [],
    this.snapshotStatus,
    this.serverRunning = false,
  });

  factory ClaudeContextReport.fromJson(Map<String, Object?> json) {
    int? count(Object? value) => value is num ? value.toInt() : null;
    final snapshot = json['snapshot'];
    return ClaudeContextReport(
      exists: json['exists'] == true,
      chunks: count(json['chunks']) ?? 0,
      indexedFiles: count(json['indexedFiles']) ?? 0,
      projectFiles: count(json['projectFiles']),
      missing: count(json['missing']),
      missingByDir: [
        if (json['missingByDir'] case final List<Object?> dirs)
          for (final dir in dirs)
            if (dir case {'dir': final String name, 'count': final num n})
              (dir: name, count: n.toInt()),
      ],
      snapshotStatus: snapshot is Map ? snapshot['status'] as String? : null,
      serverRunning: json['serverRunning'] == true,
    );
  }

  final bool exists;
  final int chunks;
  final int indexedFiles;

  /// The files the indexer means to index (its merkle snapshot); null
  /// when it has none.
  final int? projectFiles;
  final int? missing;
  final List<({String dir, int count})> missingByDir;

  /// What the server's snapshot says of it: `indexing`, `completed`…
  final String? snapshotStatus;
  final bool serverRunning;

  /// Its state, where no run of BaoCode's goes on.
  ClaudeContextState get state {
    if (snapshotStatus == 'indexing') {
      return serverRunning
          ? ClaudeContextState.indexing
          : ClaudeContextState.interrupted;
    }
    if (snapshotStatus case final status?
        when status.contains('fail') || status.contains('limit')) {
      return ClaudeContextState.failed;
    }
    if (!exists) return ClaudeContextState.notIndexed;
    return missing == 0
        ? ClaudeContextState.complete
        : ClaudeContextState.incomplete;
  }
}

/// Runs the helper with [args]: its JSON lines, each a map, as they come.
typedef ClaudeContextRunner =
    Stream<Map<String, Object?>> Function(
      List<String> args,
      Map<String, Object?> server,
    );

/// A project's index: its state, what was found, a run's progress; one per
/// project, shared by every window ([of]).
class ClaudeContextIndex extends ChangeNotifier {
  ClaudeContextIndex._(this.root, this.server);

  /// The project's folder, on this machine.
  final String root;

  /// The claude-context server's entry (`command`, `args`, `env`).
  final Map<String, Object?> server;

  static final Map<String, ClaudeContextIndex> _indexes = {};

  /// How the helper runs: node, by default; replaced under test.
  static ClaudeContextRunner runner = _runNode;

  /// Where the MCP servers are read.
  static CustomizationStore store = CustomizationStore();

  /// Whether the index is looked at: not under `flutter test`, unless a
  /// test says so (it would read the user's config and run node).
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');

  /// The claude-context server of the project at a path ([serverIn] in
  /// [store], by default); replaced under test.
  static Future<Map<String, Object?>?> Function(String root) serverOf =
      (root) => serverIn(store, root);

  /// The user's claude-context server, once found
  /// (findClaudeContextServer): the chat's sidebar's projects'.
  static Map<String, Object?>? userServer;

  /// [root]'s, where claude-context is among its MCP servers ([server]);
  /// none for a project on another machine.
  static ClaudeContextIndex? of(String root, Map<String, Object?>? server) {
    if (!enabled ||
        server == null ||
        root.isEmpty ||
        RemoteLocation.isRemote(root)) {
      return null;
    }
    return _indexes.putIfAbsent(root, () => ClaudeContextIndex._(root, server));
  }

  /// The claude-context server's entry among [project]'s MCP servers (the
  /// user's, the project's), enabled; null where there is none.
  static Future<Map<String, Object?>?> serverIn(
    CustomizationStore store,
    String project,
  ) async {
    final servers = await store.list(CustomizationKind.mcps, project: project);
    for (final server in servers) {
      if (server.name == 'claude-context' &&
          server.enabled != false &&
          server.server?['command'] is String) {
        return server.server;
      }
    }
    return null;
  }

  ClaudeContextState get state => _state;
  ClaudeContextState _state = ClaudeContextState.unknown;

  ClaudeContextReport? get report => _report;
  ClaudeContextReport? _report;

  /// While BaoCode indexes: the chunks in Milvus so far, and the share
  /// done where the server tells it (0–100).
  int? get rows => _rows;
  int? _rows;
  double? get percentage => _percentage;
  double? _percentage;

  /// Why the last look or run failed.
  String? get error => _error;
  String? _error;

  bool get busy => _state == ClaudeContextState.checking || _indexing;
  bool _indexing = false;

  /// Looks at it anew; not while indexing.
  Future<void> check() async {
    if (busy) return;
    _set(ClaudeContextState.checking);
    await _run(['check', root, '--json']);
  }

  /// Indexes it: the files changed, or ([force]) all of them again.
  Future<void> index({bool force = false}) async {
    if (_indexing) return;
    _indexing = true;
    _rows = null;
    _percentage = null;
    _set(ClaudeContextState.indexing);
    try {
      await _run(['index', root, '--json', if (force) '--force']);
    } finally {
      _indexing = false;
      if (_state == ClaudeContextState.indexing) {
        _set(_report?.state ?? ClaudeContextState.unknown);
      }
    }
  }

  Future<void> _run(List<String> args) async {
    _error = null;
    try {
      await for (final event in runner(args, server)) {
        switch (event['event']) {
          case 'check' || 'done':
            _report = ClaudeContextReport.fromJson(event);
            _set(_report!.state);
          case 'progress':
            if (event['rows'] case final num rows) _rows = rows.toInt();
            if (event['snapshot'] case {'percentage': final num share}) {
              _percentage = share.toDouble();
            }
            notifyListeners();
          case 'error':
            _error = event['message'] as String?;
            _set(ClaudeContextState.failed);
        }
      }
    } on Object catch (error) {
      _error = '$error';
      _set(ClaudeContextState.failed);
    }
  }

  void _set(ClaudeContextState state) {
    _state = state;
    notifyListeners();
  }

  /// The children the helper runs, ended at the next start if left.
  static final registry = ChildProcessRegistry(
    file: File(DataDirectory.current.processRegistryFile('claude-context')),
    recognizes: (command) => command.contains('bao_index.js'),
  );

  /// The helper, from the app's assets, where node runs it.
  static Future<String> _script() async {
    final dir = Directory(
      p.join(DataDirectory.current.cacheDir, 'claude-context'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'bao_index.js'));
    final text = await rootBundle.loadString(
      'tool/claude_context/bao_index.js',
    );
    if (!await file.exists() || await file.readAsString() != text) {
      await writeFileAtomically(file, text);
    }
    return file.path;
  }

  /// The node the server runs on, else one where Homebrew or the system
  /// keeps it (an app's PATH has neither).
  static String _node(Map<String, Object?> server) {
    final command = server['command'];
    if (command is String && p.basename(command).startsWith('node')) {
      return command;
    }
    for (final candidate in const [
      '/opt/homebrew/bin/node',
      '/usr/local/bin/node',
      '/usr/bin/node',
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    return 'node';
  }

  static Stream<Map<String, Object?>> _runNode(
    List<String> args,
    Map<String, Object?> server,
  ) async* {
    await registry.reaped;
    final process = await Process.start(_node(server), [
      await _script(),
      ...args,
      '--server',
      jsonEncode(server),
    ]);
    unawaited(registry.add(process.pid));
    unawaited(process.stderr.drain<void>());
    try {
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        try {
          if (jsonDecode(line) case final Map<String, Object?> event) {
            yield event;
          }
        } on FormatException {
          continue;
        }
      }
      await process.exitCode;
    } finally {
      unawaited(registry.remove(process.pid));
    }
  }

  @visibleForTesting
  static void forgetAll() => _indexes.clear();
}
