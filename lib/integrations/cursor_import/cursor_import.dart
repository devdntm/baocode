// A project's Cursor setup brought over (docs/fork.md): its rules
// (`.cursor/rules/*.mdc`, `.cursorrules`) as Claude Code's
// (`.claude/rules/*.md`), its MCP servers (`.cursor/mcp.json`) into
// `.mcp.json`, its agents' conversations (~/.cursor/projects/<project>/
// agent-transcripts) into memsearch's memory, and Cursor's themes. None of
// it overwrites what the project has.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../extensions/theme_extensions.dart';
import '../../platform/data_dir.dart';
import '../../remote/remote_location.dart';

/// A rule of Cursor's, as it would be Claude Code's.
@immutable
class CursorRuleImport {
  const CursorRuleImport({
    required this.source,
    required this.target,
    required this.text,
    required this.exists,
    this.alwaysNow = false,
  });

  final String source;

  /// Its file under `.claude/rules`.
  final String target;
  final String text;

  /// Whether the project has a rule there already: not overwritten.
  final bool exists;

  /// Cursor applied it only where relevant (by its description); Claude
  /// Code reads it always.
  final bool alwaysNow;
}

/// A skill of Cursor's: the same `SKILL.md` as Claude Code's, its folder
/// copied as it is.
@immutable
class CursorSkillImport {
  const CursorSkillImport({
    required this.source,
    required this.target,
    required this.text,
    required this.description,
    required this.exists,
  });

  /// Its folder under `.cursor/skills`.
  final String source;

  /// Its folder under `.claude/skills`.
  final String target;

  /// Its `SKILL.md`.
  final String text;
  final String description;

  /// Whether the project has a skill there already: not overwritten.
  final bool exists;

  String get name => p.basename(target);
}

/// [mdc], a rule of Cursor's, as Claude Code's: `globs` as `paths`,
/// `alwaysApply` and `description` gone (Claude Code reads a rule without
/// `paths` always). Whether it was applied only where relevant in Cursor.
(String, bool) convertCursorRule(String mdc) {
  final lines = const LineSplitter().convert(mdc);
  Map<Object?, Object?> meta = const {};
  var body = mdc;
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    final end = lines.indexWhere((line) => line.trim() == '---', 1);
    if (end > 0) {
      try {
        if (loadYaml(lines.sublist(1, end).join('\n')) case final Map map) {
          meta = map;
        }
      } on YamlException {
        meta = const {};
      }
      body = lines.sublist(end + 1).join('\n');
    }
  }
  final globs = <String>[
    ...switch (meta['globs']) {
      final String text => text.split(','),
      final List<Object?> list => [for (final item in list) '$item'],
      _ => const <String>[],
    },
  ].map((glob) => glob.trim()).where((glob) => glob.isNotEmpty).toList();
  body = body.replaceFirst(RegExp(r'^\s*\n'), '');
  final always = meta['alwaysApply'] == true;
  if (globs.isEmpty) {
    return ('${body.trimRight()}\n', !always && meta.isNotEmpty);
  }
  return (
    [
      '---',
      'paths:',
      for (final glob in globs) '  - ${jsonEncode(glob)}',
      '---',
      '',
      body.trimRight(),
      '',
    ].join('\n'),
    false,
  );
}

/// [server], one of Cursor's MCP servers, as Claude Code's `.mcp.json` has
/// them: `${env:NAME}` as `${NAME}`, a URL's an `http` one.
Map<String, Object?> convertCursorServer(Map<String, Object?> server) {
  Object? convert(Object? value) => switch (value) {
    final String text => text.replaceAllMapped(
      RegExp(r'\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}'),
      (match) => '\${${match[1]}}',
    ),
    final List<Object?> list => [for (final item in list) convert(item)],
    final Map<String, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) key: convert(value),
    },
    _ => value,
  };
  final converted = convert(server)! as Map<String, Object?>;
  if (converted['url'] != null && converted['type'] == null) {
    return {'type': 'http', ...converted};
  }
  return converted;
}

/// What a project has of Cursor's to bring over.
class CursorProject {
  CursorProject._({
    required this.root,
    required this.rules,
    required this.skills,
    required this.servers,
    required this.serversHad,
    required this.transcripts,
    required this.sessions,
  });

  final String root;
  final List<CursorRuleImport> rules;
  final List<CursorSkillImport> skills;

  /// Cursor's MCP servers the project's `.mcp.json` has not.
  final Map<String, Map<String, Object?>> servers;

  /// Those it has already, by name.
  final List<String> serversHad;

  /// Where Cursor keeps the project's agents' conversations; none when
  /// there are none.
  final String? transcripts;
  final int sessions;

  /// The user's home; replaced under test.
  static String home = Platform.environment['HOME'] ?? '';

  /// Cursor's folder of [root] (its path, every character but letters
  /// and digits a dash, as Cursor names it).
  static String folderOf(String root) => p.join(
    home,
    '.cursor',
    'projects',
    root
        .replaceAll(RegExp('[^A-Za-z0-9]'), '-')
        .replaceFirst(RegExp('^-+'), ''),
  );

  /// Whether [root] has anything of Cursor's at a glance: its `.cursor`,
  /// `.cursorrules`, or Cursor's folder of it.
  static bool seen(String root) {
    if (root.isEmpty || RemoteLocation.isRemote(root)) return false;
    return Directory(p.join(root, '.cursor')).existsSync() ||
        File(p.join(root, '.cursorrules')).existsSync() ||
        Directory(p.join(folderOf(root), 'agent-transcripts')).existsSync();
  }

  bool get isEmpty =>
      rules.isEmpty && skills.isEmpty && servers.isEmpty && sessions == 0;

  /// What [root] has of Cursor's.
  static Future<CursorProject> read(String root) async {
    final rules = <CursorRuleImport>[];
    final target = p.join(root, '.claude', 'rules');
    Future<void> rule(String source, String name) async {
      final (text, alwaysNow) = convertCursorRule(
        await File(source).readAsString(),
      );
      final path = p.join(target, name);
      rules.add(
        CursorRuleImport(
          source: source,
          target: path,
          text: text,
          exists: await File(path).exists(),
          alwaysNow: alwaysNow,
        ),
      );
    }

    final cursorRules = Directory(p.join(root, '.cursor', 'rules'));
    if (await cursorRules.exists()) {
      final files = await cursorRules
          .list(recursive: true)
          .where((entry) => entry is File && entry.path.endsWith('.mdc'))
          .map((entry) => entry.path)
          .toList();
      files.sort();
      for (final file in files) {
        final relative = p.relative(file, from: cursorRules.path);
        await rule(file, '${p.withoutExtension(relative)}.md');
      }
    }
    final legacy = File(p.join(root, '.cursorrules'));
    if (await legacy.exists()) await rule(legacy.path, 'cursorrules.md');

    final skills = <CursorSkillImport>[];
    final cursorSkills = Directory(p.join(root, '.cursor', 'skills'));
    if (await cursorSkills.exists()) {
      final folders = await cursorSkills
          .list()
          .where((entry) => entry is Directory)
          .map((entry) => entry.path)
          .toList();
      folders.sort();
      for (final folder in folders) {
        final skill = File(p.join(folder, 'SKILL.md'));
        if (!await skill.exists()) continue;
        final text = await skill.readAsString();
        final path = p.join(root, '.claude', 'skills', p.basename(folder));
        skills.add(
          CursorSkillImport(
            source: folder,
            target: path,
            text: text,
            description: _skillDescription(text),
            exists: await Directory(path).exists(),
          ),
        );
      }
    }

    final servers = <String, Map<String, Object?>>{};
    final had = <String>[];
    final cursorMcp = await _json(p.join(root, '.cursor', 'mcp.json'));
    final ours = await _json(p.join(root, '.mcp.json'));
    final ourServers = switch (ours?['mcpServers']) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    if (cursorMcp?['mcpServers'] case final Map<String, Object?> theirs) {
      for (final MapEntry(key: name, value: server) in theirs.entries) {
        if (server is! Map<String, Object?>) continue;
        if (ourServers.containsKey(name)) {
          had.add(name);
        } else {
          servers[name] = convertCursorServer(server);
        }
      }
    }

    final transcripts = Directory(p.join(folderOf(root), 'agent-transcripts'));
    var sessions = 0;
    if (await transcripts.exists()) {
      await for (final entry in transcripts.list()) {
        if (entry is Directory) sessions++;
      }
    }
    return CursorProject._(
      root: root,
      rules: rules,
      skills: skills,
      servers: servers,
      serversHad: had,
      transcripts: sessions == 0 ? null : transcripts.path,
      sessions: sessions,
    );
  }

  /// The `description` of a `SKILL.md`'s front matter.
  static String _skillDescription(String text) {
    final match = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---').firstMatch(text);
    if (match == null) return '';
    try {
      if (loadYaml(match[1]!) case {'description': final Object description}) {
        return '$description'.trim();
      }
    } on YamlException {
      return '';
    }
    return '';
  }

  static Future<Map<String, Object?>?> _json(String path) async {
    try {
      final json = jsonDecode(await File(path).readAsString());
      return json is Map<String, Object?> ? json : null;
    } on Object {
      return null;
    }
  }

  /// Writes [rules] the project has not: their paths.
  Future<List<String>> importRules(Iterable<CursorRuleImport> rules) async {
    final written = <String>[];
    for (final rule in rules) {
      final file = File(rule.target);
      if (await file.exists()) continue;
      await file.parent.create(recursive: true);
      await writeFileAtomically(file, rule.text);
      written.add(rule.target);
    }
    return written;
  }

  /// Copies [skills] the project has not, each folder whole (into a
  /// folder beside it first, so a copy cut short is no skill): their
  /// paths.
  Future<List<String>> importSkills(Iterable<CursorSkillImport> skills) async {
    final written = <String>[];
    for (final skill in skills) {
      final target = Directory(skill.target);
      if (await target.exists()) continue;
      await target.parent.create(recursive: true);
      final temp = await target.parent.createTemp('.${skill.name}-');
      try {
        await for (final entry in Directory(
          skill.source,
        ).list(recursive: true, followLinks: false)) {
          final path = p.join(
            temp.path,
            p.relative(entry.path, from: skill.source),
          );
          switch (entry) {
            case Directory():
              await Directory(path).create(recursive: true);
            case File():
              await Directory(p.dirname(path)).create(recursive: true);
              await entry.copy(path);
            case Link():
              await Directory(p.dirname(path)).create(recursive: true);
              await Link(path).create(await entry.target());
          }
        }
        await temp.rename(target.path);
      } on Object {
        if (await temp.exists()) await temp.delete(recursive: true);
        rethrow;
      }
      written.add(skill.target);
    }
    return written;
  }

  /// Adds [names] of [servers] to the project's `.mcp.json`, what it has
  /// kept as it was.
  Future<void> importServers(Iterable<String> names) async {
    if (names.isEmpty) return;
    final path = p.join(root, '.mcp.json');
    final json = await _json(path) ?? <String, Object?>{};
    final mcp = {
      ...switch (json['mcpServers']) {
        final Map<String, Object?> map => map,
        _ => const <String, Object?>{},
      },
    };
    for (final name in names) {
      if (servers[name] case final server? when !mcp.containsKey(name)) {
        mcp[name] = server;
      }
    }
    await writeFileAtomically(
      File(path),
      '${const JsonEncoder.withIndent('  ').convert({...json, 'mcpServers': mcp})}\n',
    );
  }
}

/// Where Cursor's own themes are: in its app.
const cursorThemesFolder =
    '/Applications/Cursor.app/Contents/Resources/app/extensions/theme-cursor';

/// Installs Cursor's themes (Cursor Dark Midnight…) as an extension of
/// [themes]: its folder packed as a .vsix, a publisher given.
Future<void> importCursorThemes(
  ThemeExtensions themes, {
  String folder = cursorThemesFolder,
}) async {
  final temp = await Directory.systemTemp.createTemp('baocode-cursor-themes');
  try {
    final extension = Directory(p.join(temp.path, 'pack', 'extension'));
    await extension.create(recursive: true);
    final copy = await Process.run('/bin/cp', [
      '-R',
      '$folder/.',
      extension.path,
    ]);
    if (copy.exitCode != 0) throw StateError('${copy.stderr}');
    final manifest = File(p.join(extension.path, 'package.json'));
    final json =
        jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
    await manifest.writeAsString(jsonEncode({'publisher': 'cursor', ...json}));
    final vsix = p.join(temp.path, 'cursor-themes.vsix');
    final zip = await Process.run('/usr/bin/ditto', [
      '-c',
      '-k',
      '--sequesterRsrc',
      p.join(temp.path, 'pack'),
      vsix,
    ]);
    if (zip.exitCode != 0) throw StateError('${zip.stderr}');
    await themes.install(vsix);
  } finally {
    await temp.delete(recursive: true);
  }
}

/// Where a history's import is.
enum CursorHistoryStage {
  idle,
  counting,
  summarizing,
  assembling,
  indexing,
  done,
  failed,
}

/// Cursor's conversations of a project into memsearch's memory: each turn
/// told in short by the model memsearch's own hook uses (paid, and long:
/// [count] first), laid out in its daily journals, indexed. Kept by the
/// project, to be followed again.
class CursorHistoryImport extends ChangeNotifier {
  CursorHistoryImport._(this.root, this.transcripts);

  final String root;
  final String transcripts;

  static final Map<String, CursorHistoryImport> _imports = {};

  static CursorHistoryImport of(String root, String transcripts) => _imports
      .putIfAbsent(root, () => CursorHistoryImport._(root, transcripts));

  CursorHistoryStage get stage => _stage;
  CursorHistoryStage _stage = CursorHistoryStage.idle;

  /// Turns to tell in short (not told before), and those told so far.
  int? get total => _total;
  int? _total;
  int get done => _done;
  int _done = 0;
  int get failed => _failed;
  int _failed = 0;
  String? get error => _error;
  String? _error;

  bool get running => switch (_stage) {
    CursorHistoryStage.counting ||
    CursorHistoryStage.summarizing ||
    CursorHistoryStage.assembling ||
    CursorHistoryStage.indexing => true,
    _ => false,
  };

  /// Whether memsearch is there to take it: its plugin's prompt, its CLI.
  static bool get available =>
      _summarizePrompt() != null && _memsearch() != null;

  String get _memory => p.join(root, '.memsearch', 'memory');
  String get _cache => p.join(root, '.memsearch', 'cursor-import-cache');

  /// How many turns are still to be told in short.
  Future<void> count() async {
    if (running) return;
    _set(CursorHistoryStage.counting);
    try {
      final lines = await _python(['count', transcripts, _cache]);
      _total = int.tryParse(lines.lastOrNull?.split(' ').first ?? '');
      _set(CursorHistoryStage.idle);
    } on Object catch (error) {
      _fail(error);
    }
  }

  /// Tells the turns in short, lays them out, indexes the memory.
  Future<void> run() async {
    if (running) return;
    _done = 0;
    _failed = 0;
    _error = null;
    _set(CursorHistoryStage.summarizing);
    try {
      await _python(
        ['summarize', transcripts, _cache, '--jobs', '4'],
        onLine: (line) {
          final match = RegExp(
            r'^progress (\d+)/(\d+) \(failed (\d+)\)',
          ).firstMatch(line);
          if (match == null) return;
          _done = int.parse(match[1]!);
          _total = int.parse(match[2]!);
          _failed = int.parse(match[3]!);
          notifyListeners();
        },
      );
      _set(CursorHistoryStage.assembling);
      await Directory(_memory).create(recursive: true);
      await _python(['assemble', transcripts, _cache, _memory]);
      _set(CursorHistoryStage.indexing);
      await _index();
      _set(CursorHistoryStage.done);
    } on Object catch (error) {
      _fail(error);
    }
  }

  /// `memsearch index` of the memory, in the collection memsearch's hooks
  /// name for the project.
  Future<void> _index() async {
    final memsearch = _memsearch()!;
    final derive = p.join(
      p.dirname(p.dirname(_summarizePrompt()!)),
      'scripts',
      'derive-collection.sh',
    );
    var collection = '';
    if (File(derive).existsSync()) {
      final named = await Process.run('/bin/bash', [derive, root]);
      collection = '${named.stdout}'.trim();
    }
    final result = await Process.run(memsearch, [
      'index',
      _memory,
      if (collection.isNotEmpty) ...['--default-collection', collection],
    ], workingDirectory: root);
    if (result.exitCode != 0) throw StateError('${result.stderr}'.trim());
  }

  Future<List<String>> _python(
    List<String> args, {
    ValueChanged<String>? onLine,
  }) async {
    final script = await _script();
    final process = await Process.start(
      _pythonBin(),
      ['-I', script, ...args],
      environment: {'CLAUDE_BIN': _claude()},
    );
    unawaited(process.stderr.drain<void>());
    final lines = <String>[];
    await for (final line
        in process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      lines.add(line);
      onLine?.call(line);
    }
    final code = await process.exitCode;
    if (code != 0) {
      throw StateError(lines.lastOrNull ?? 'exited with $code');
    }
    return lines;
  }

  void _set(CursorHistoryStage stage) {
    _stage = stage;
    notifyListeners();
  }

  void _fail(Object error) {
    _error = '$error';
    _set(CursorHistoryStage.failed);
  }

  static String? _summarizePrompt() {
    final root = Directory(
      p.join(
        CursorProject.home,
        '.claude',
        'plugins',
        'cache',
        'memsearch-plugins',
        'memsearch',
      ),
    );
    if (!root.existsSync()) return null;
    final prompts = [
      for (final version in root.listSync().whereType<Directory>())
        p.join(version.path, 'prompts', 'summarize.txt'),
    ].where((path) => File(path).existsSync()).toList()..sort();
    return prompts.lastOrNull;
  }

  static String? _memsearch() => _first([
    p.join(CursorProject.home, '.local', 'bin', 'memsearch'),
    '/opt/homebrew/bin/memsearch',
    '/usr/local/bin/memsearch',
  ]);

  static String _pythonBin() =>
      _first(['/opt/homebrew/bin/python3', '/usr/bin/python3']) ?? 'python3';

  /// The Claude Code that tells the turns in short: BaoCode's own, else
  /// the user's.
  static String _claude() =>
      _first([
        p.join(DataDirectory.current.path, 'claude', 'bin', 'claude'),
        p.join(CursorProject.home, '.local', 'bin', 'claude'),
      ]) ??
      'claude';

  static String? _first(List<String> paths) {
    for (final path in paths) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  static Future<String> _script() async {
    final dir = Directory(
      p.join(DataDirectory.current.cacheDir, 'cursor-import'),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, 'cursor_memsearch_import.py'));
    final text = await rootBundle.loadString(
      'tool/cursor_import/cursor_memsearch_import.py',
    );
    if (!await file.exists() || await file.readAsString() != text) {
      await writeFileAtomically(file, text);
    }
    return file.path;
  }

  @visibleForTesting
  static void forgetAll() => _imports.clear();
}
